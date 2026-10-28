#ifndef LOCALE_EDITOR_BRIDGE_H
#define LOCALE_EDITOR_BRIDGE_H
#include <stddef.h>
// Swift cannot call C variadic functions. These fixed-signature wrappers use the active locale.
int le_format_number(char *buffer, size_t size, double value);
long le_format_money(char *buffer, size_t size, double value);
long le_format_international_money(char *buffer, size_t size, double value);
int le_terminal_columns(void);
int le_terminal_rows(void);
int le_terminal_enter(void);
void le_terminal_leave(void);
int le_display_width(unsigned int scalar);
int le_regex_match(const char *pattern, const char *sample, char *error, size_t size);
unsigned int le_character_classes(unsigned int scalar);
unsigned int le_character_upper(unsigned int scalar);
unsigned int le_character_lower(unsigned int scalar);
int le_transliterate(const char *input, char *output, size_t size);
// Keep an interactive child in the terminal's foreground process group.
int le_spawn_attached(const char *path, char *const arguments[], int output_fd);
int le_wait_attached(int process_id);
// Noninteractive workers use POSIX spawning/reaping rather than a Foundation run loop.
int le_spawn_capture(const char *path, char *const arguments[], char *const environment[], int output_fd, int *error_code);
int le_poll_process(int process_id, int *exit_status);
int le_reap_process(int process_id);
int le_file_identity(const char *path, unsigned int *device_major, unsigned int *device_minor, unsigned long long *inode);
#endif
