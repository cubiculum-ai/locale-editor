#define _XOPEN_SOURCE 700
#include "CLocaleBridge.h"
#include <stdio.h>
#include <monetary.h>
#include <sys/ioctl.h>
#include <unistd.h>
#include <termios.h>
#include <signal.h>
#include <stdlib.h>
#include <wchar.h>
#include <wctype.h>
#include <regex.h>
#include <string.h>
#ifdef __linux__
#include <iconv.h>
#endif
#include <sys/wait.h>
#include <errno.h>
#include <sys/stat.h>
#include <spawn.h>
#include <fcntl.h>
#ifdef __linux__
#include <sys/sysmacros.h>
#endif

int le_regex_match(const char *pattern, const char *sample, char *error, size_t size) {
    regex_t regex;
    int code = regcomp(&regex, pattern, REG_EXTENDED | REG_NOSUB);
    if (code) { regerror(code, &regex, error, size); return -1; }
    code = regexec(&regex, sample, 0, NULL, 0);
    if (code != 0 && code != REG_NOMATCH) regerror(code, &regex, error, size);
    regfree(&regex);
    return code == 0 ? 1 : code == REG_NOMATCH ? 0 : -1;
}
unsigned int le_character_classes(unsigned int c) {
    return (iswalpha(c) ? 1 : 0) | (iswdigit(c) ? 2 : 0) | (iswspace(c) ? 4 : 0)
        | (iswpunct(c) ? 8 : 0) | (iswupper(c) ? 16 : 0) | (iswlower(c) ? 32 : 0)
        | (iswprint(c) ? 64 : 0) | (iswcntrl(c) ? 128 : 0);
}
unsigned int le_character_upper(unsigned int c) { return towupper(c); }
unsigned int le_character_lower(unsigned int c) { return towlower(c); }
int le_transliterate(const char *input, char *output, size_t size) {
#ifdef __linux__
    if (!size) return -1;
    iconv_t converter = iconv_open("ASCII//TRANSLIT", "UTF-8");
    if (converter == (iconv_t)-1) return -1;
    char *source = (char *)input, *target = output;
    size_t remaining = strlen(input), available = size - 1;
    size_t converted = iconv(converter, &source, &remaining, &target, &available);
    int result = converted == (size_t)-1 ? -1 : 0;
    *target = '\0';
    iconv_close(converter);
    return result;
#else
    (void)input; (void)output; (void)size;
    return -1;
#endif
}

int le_file_identity(const char *path, unsigned int *device_major, unsigned int *device_minor, unsigned long long *inode) {
#ifdef __linux__
    struct stat info;
    if (stat(path, &info) != 0 || !S_ISREG(info.st_mode)) return -1;
    *device_major = major(info.st_dev);
    *device_minor = minor(info.st_dev);
    *inode = (unsigned long long)info.st_ino;
    return 0;
#else
    (void)path; (void)device_major; (void)device_minor; (void)inode;
    return -1;
#endif
}

int le_spawn_attached(const char *path, char *const arguments[], int output_fd) {
    pid_t child = fork();
    if (child != 0) return (int)child;
    /* Only async-signal-safe operations between fork and exec. */
    signal(SIGINT, SIG_DFL);
    signal(SIGTERM, SIG_DFL);
    signal(SIGHUP, SIG_DFL);
    if (dup2(output_fd, STDOUT_FILENO) < 0) _exit(127);
    if (output_fd != STDOUT_FILENO) close(output_fd);
    execv(path, arguments);
    const char failure[] = "Could not launch the administrator tool.\n";
    (void)write(STDERR_FILENO, failure, sizeof(failure) - 1);
    _exit(127);
}
int le_wait_attached(int process_id) {
    int status;
    pid_t result;
    do { result = waitpid((pid_t)process_id, &status, 0); } while (result < 0 && errno == EINTR);
    if (result < 0) return -1;
    if (WIFEXITED(status)) return WEXITSTATUS(status);
    if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
    return -1;
}

int le_spawn_capture(const char *path, char *const arguments[], char *const environment[], int output_fd, int *error_code) {
    // Keep the redirected file above stdin/stdout/stderr even if the caller closed one.
    int descriptor=fcntl(output_fd,F_DUPFD_CLOEXEC,3);
    if(descriptor<0){*error_code=errno;return -1;}
    posix_spawn_file_actions_t actions;
    posix_spawnattr_t attributes;
    int error=posix_spawn_file_actions_init(&actions);
    if(error){close(descriptor);*error_code=error;return -1;}
    error=posix_spawnattr_init(&attributes);
    if(error){posix_spawn_file_actions_destroy(&actions);close(descriptor);*error_code=error;return -1;}
    sigset_t mask,defaults;
    sigemptyset(&mask);sigemptyset(&defaults);
    sigaddset(&defaults,SIGINT);sigaddset(&defaults,SIGTERM);sigaddset(&defaults,SIGHUP);
    sigaddset(&defaults,SIGQUIT);sigaddset(&defaults,SIGPIPE);
    if(!error)error=posix_spawnattr_setsigmask(&attributes,&mask);
    if(!error)error=posix_spawnattr_setsigdefault(&attributes,&defaults);
    if(!error)error=posix_spawnattr_setpgroup(&attributes,0);
    if(!error)error=posix_spawnattr_setflags(&attributes,POSIX_SPAWN_SETSIGMASK|POSIX_SPAWN_SETSIGDEF|POSIX_SPAWN_SETPGROUP);
    if(!error)error=posix_spawn_file_actions_addopen(&actions,STDIN_FILENO,"/dev/null",O_RDONLY,0);
    if(!error)error=posix_spawn_file_actions_adddup2(&actions,descriptor,STDOUT_FILENO);
    if(!error)error=posix_spawn_file_actions_adddup2(&actions,descriptor,STDERR_FILENO);
    if(!error)error=posix_spawn_file_actions_addclose(&actions,descriptor);
    pid_t pid=-1;
    if(!error)error=posix_spawn(&pid,path,&actions,&attributes,arguments,environment);
    posix_spawnattr_destroy(&attributes);posix_spawn_file_actions_destroy(&actions);close(descriptor);
    *error_code=error;return error ? -1 : (int)pid;
}
static int exit_status(int status) {
    return WIFEXITED(status) ? WEXITSTATUS(status) : WIFSIGNALED(status) ? 128+WTERMSIG(status) : -1;
}
int le_poll_process(int process_id,int *status) {
    int raw;pid_t result;
    do {result=waitpid((pid_t)process_id,&raw,WNOHANG);} while(result<0 && errno==EINTR);
    if(result>0){*status=exit_status(raw);return 1;}
    return result<0 ? -1 : 0;
}
int le_reap_process(int process_id) {
    int raw;pid_t result;
    do {result=waitpid((pid_t)process_id,&raw,0);} while(result<0 && errno==EINTR);
    return result<0 ? -1 : exit_status(raw);
}
static struct termios original;
static volatile sig_atomic_t terminal_active = 0;
void le_terminal_leave(void) {
    if (!terminal_active) return;
    terminal_active = 0;
    tcsetattr(STDIN_FILENO, TCSANOW, &original);
    const char restore[] = "\033[?1006l\033[?1000l\033[0m\033[?25h\033[?1049l";
    (void)write(STDOUT_FILENO, restore, sizeof(restore) - 1);
}
static void interrupted(int sig) {
    /* While sudo owns the cooked terminal, Ctrl-C should cancel that child, not
       discard the editor's unsaved state. Caught handlers reset on child exec. */
    if (!terminal_active && sig == SIGINT) return;
    le_terminal_leave();
    _exit(128 + sig);
}
int le_terminal_enter(void) {
    if (!isatty(STDIN_FILENO) || !isatty(STDOUT_FILENO)) return -1;
    if (tcgetattr(STDIN_FILENO, &original) != 0) return -1;
    struct termios raw = original;
    raw.c_iflag &= ~(BRKINT | ICRNL | INPCK | ISTRIP | IXON);
    raw.c_oflag &= ~OPOST;
    raw.c_cflag |= CS8;
    raw.c_lflag &= ~(ECHO | ICANON | IEXTEN | ISIG);
    raw.c_cc[VMIN] = 0;
    raw.c_cc[VTIME] = 1;
    if (tcsetattr(STDIN_FILENO, TCSANOW, &raw) != 0) return -1;
    terminal_active = 1;
    atexit(le_terminal_leave);
    signal(SIGTERM, interrupted);
    signal(SIGHUP, interrupted);
    signal(SIGINT, interrupted);
    const char enter[] = "\033[?1049h\033[?25l\033[?1000h\033[?1006h";
    (void)write(STDOUT_FILENO, enter, sizeof(enter) - 1);
    return 0;
}
int le_display_width(unsigned int scalar) { return wcwidth((wchar_t)scalar); }
int le_format_number(char *buffer, size_t size, double value) {
    return snprintf(buffer, size, "%'.2f", value);
}
long le_format_money(char *buffer, size_t size, double value) {
    return (long)strfmon(buffer, size, "%n", value);
}
long le_format_international_money(char *buffer, size_t size, double value) {
    return (long)strfmon(buffer, size, "%i", value);
}
int le_terminal_columns(void) {
    struct winsize w = {0};
    return ioctl(STDOUT_FILENO, TIOCGWINSZ, &w) == 0 && w.ws_col ? w.ws_col : 100;
}
int le_terminal_rows(void) {
    struct winsize w = {0};
    return ioctl(STDOUT_FILENO, TIOCGWINSZ, &w) == 0 && w.ws_row ? w.ws_row : 30;
}
