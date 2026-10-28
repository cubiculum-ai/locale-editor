#ifndef LOCALE_EDITOR_GTK_BRIDGE_H
#define LOCALE_EDITOR_GTK_BRIDGE_H
#include <stddef.h>
typedef struct LEGUI LEGUI;
typedef void (*LEGUIEvent)(void *context, const char *action, int index, const char *text);
typedef void (*LEGUIIdle)(void *context);
LEGUI *legui_create(LEGUIEvent callback, void *context);
int legui_run(LEGUI *gui);
void legui_quit(LEGUI *gui);
void legui_destroy(LEGUI *gui);
void legui_idle(LEGUIIdle callback, void *context);
void legui_title(LEGUI *gui, const char *title);
void legui_section_add(LEGUI *gui, const char *title);
void legui_section_select(LEGUI *gui, int index);
void legui_heading(LEGUI *gui, const char *title, const char *source, const char *description);
void legui_fields_clear(LEGUI *gui);
void legui_field_add(LEGUI *gui, const char *label, const char *value, const char *example, const char *origin);
void legui_field_select(LEGUI *gui, int index);
void legui_examples(LEGUI *gui, const char *text);
void legui_status(LEGUI *gui, const char *text);
void legui_help(LEGUI *gui, const char *text);
void legui_busy(LEGUI *gui, int busy);
void legui_history(LEGUI *gui, int undo, int redo);
void legui_message(LEGUI *gui, const char *title, const char *text);
int legui_confirm(LEGUI *gui, const char *title, const char *text, const char *accept);
char *legui_file(LEGUI *gui, int mode, const char *title, const char *initial);
char *legui_prompt(LEGUI *gui, const char *title, const char *initial, const char *help);
void legui_prompt_example(LEGUI *gui, const char *text);
void *legui_choices(LEGUI *gui, const char *title, int custom);
void legui_choice_add(void *dialog, const char *id, const char *label, const char *example, const char *detail);
char *legui_choice_run(void *dialog, const char *initial);
void legui_free(char *text);
#endif
