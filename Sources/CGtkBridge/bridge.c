#include "CGtkBridge.h"
#include <gtk/gtk.h>
#include <string.h>

struct LEGUI {
    GtkApplication *application;
    GtkWidget *window, *menus, *pane, *sections, *fields, *heading, *source, *description;
    GtkWidget *examples, *status, *help, *spinner, *undo, *redo, *prompt_preview;
    GtkListStore *section_store, *field_store;
    LEGUIEvent callback; void *context;
    gboolean updating;
    GList *events;
};
typedef struct { LEGUI *gui; const char *action; } Action;
typedef struct { LEGUI *gui; const char *action; int index; guint source; } QueuedEvent;
static void emit(LEGUI *g, const char *action, int index, const char *text) { g->callback(g->context, action, index, text ? text : ""); }
// Open modal dialogs only after the originating GTK/AT-SPI signal has returned.
static gboolean event_run(gpointer data) {
    QueuedEvent *event=data;
    event->gui->events=g_list_remove(event->gui->events,event);
    emit(event->gui,event->action,event->index,"");
    return G_SOURCE_REMOVE;
}
static void dispatch(LEGUI *gui,const char *action,int index) {
    QueuedEvent *event=g_new0(QueuedEvent,1);
    event->gui=gui;event->action=action;event->index=index;
    event->source=g_idle_add_full(G_PRIORITY_DEFAULT_IDLE,event_run,event,g_free);
    gui->events=g_list_prepend(gui->events,event);
}
static void action_free(gpointer data, GClosure *closure) { (void)closure; g_free(data); }
static void action_run(GtkWidget *widget, gpointer data) {
    Action *a=data;
    if(GTK_IS_MENU_ITEM(widget)) {
        GtkWidget *parent=gtk_widget_get_parent(widget);
        if(GTK_IS_MENU_SHELL(parent)) gtk_menu_shell_deactivate(GTK_MENU_SHELL(parent));
    }
    dispatch(a->gui,a->action,0);
}
static void bind_action(LEGUI *g, GtkWidget *w, const char *signal, const char *action) {
    Action *a=g_new0(Action,1); a->gui=g; a->action=action;
    g_signal_connect_data(w,signal,G_CALLBACK(action_run),a,action_free,0);
}
static GtkWidget *label(const char *text) { GtkWidget *w=gtk_label_new(text); gtk_label_set_xalign(GTK_LABEL(w),0); gtk_label_set_line_wrap(GTK_LABEL(w),TRUE); return w; }
static GtkWidget *scrolled(GtkWidget *child) { GtkWidget *w=gtk_scrolled_window_new(NULL,NULL); gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(w),GTK_POLICY_AUTOMATIC,GTK_POLICY_AUTOMATIC); gtk_container_add(GTK_CONTAINER(w),child); return w; }
static GtkWidget *text_view(void) {
    GtkWidget *v=gtk_text_view_new(); gtk_text_view_set_editable(GTK_TEXT_VIEW(v),FALSE);
    gtk_text_view_set_cursor_visible(GTK_TEXT_VIEW(v),FALSE); gtk_text_view_set_wrap_mode(GTK_TEXT_VIEW(v),GTK_WRAP_WORD_CHAR);
    gtk_text_view_set_left_margin(GTK_TEXT_VIEW(v),8); gtk_text_view_set_right_margin(GTK_TEXT_VIEW(v),8);
    gtk_text_view_set_top_margin(GTK_TEXT_VIEW(v),6); return v;
}
static void text_set(GtkWidget *view,const char *text) { gtk_text_buffer_set_text(gtk_text_view_get_buffer(GTK_TEXT_VIEW(view)),text,-1); }
static int selected_index(GtkTreeSelection *selection) {
    GtkTreeIter iter; GtkTreeModel *model;
    if (!gtk_tree_selection_get_selected(selection,&model,&iter)) return -1;
    GtkTreePath *p=gtk_tree_model_get_path(model,&iter); int i=gtk_tree_path_get_indices(p)[0]; gtk_tree_path_free(p); return i;
}
static void section_changed(GtkTreeSelection *selection,gpointer data) { LEGUI *g=data; if(!g->updating) dispatch(g,"section",selected_index(selection)); }
static void field_changed(GtkTreeSelection *selection,gpointer data) { LEGUI *g=data; if(!g->updating) emit(g,"field",selected_index(selection),""); }
static void field_activated(GtkTreeView *tree,GtkTreePath *path,GtkTreeViewColumn *column,gpointer data) { (void)tree;(void)column; dispatch(data,"preset",gtk_tree_path_get_indices(path)[0]); }
static gboolean closing(GtkWidget *w,GdkEvent *event,gpointer data) { (void)w;(void)event;dispatch(data,"quit",0);return TRUE; }
static GtkWidget *menu(LEGUI *g,GtkWidget *bar,const char *name) { (void)g; GtkWidget *item=gtk_menu_item_new_with_mnemonic(name),*sub=gtk_menu_new();gtk_menu_item_set_submenu(GTK_MENU_ITEM(item),sub);gtk_menu_shell_append(GTK_MENU_SHELL(bar),item);return sub; }
static GtkWidget *menu_item(LEGUI *g,GtkWidget *menu,const char *name,const char *action,GtkAccelGroup *accel,guint key,GdkModifierType mods) {
    GtkWidget *item=gtk_menu_item_new_with_mnemonic(name);gtk_menu_shell_append(GTK_MENU_SHELL(menu),item);bind_action(g,item,"activate",action);
    if(key) gtk_widget_add_accelerator(item,"activate",accel,key,mods,GTK_ACCEL_VISIBLE);return item;
}
static void button(LEGUI *g,GtkWidget *box,const char *name,const char *action) { GtkWidget *b=gtk_button_new_with_mnemonic(name);gtk_box_pack_start(GTK_BOX(box),b,FALSE,FALSE,0);bind_action(g,b,"clicked",action); }
static void activate(GtkApplication *application,gpointer data) {
    LEGUI *g=data;
    g->window=gtk_application_window_new(application);gtk_window_set_default_size(GTK_WINDOW(g->window),1120,760);
    gtk_window_set_title(GTK_WINDOW(g->window),"Linux Locale Editor");gtk_window_set_icon_name(GTK_WINDOW(g->window),"org.linuxlocaleeditor.Editor");
    g_signal_connect(g->window,"delete-event",G_CALLBACK(closing),g);
    GtkWidget *outer=gtk_box_new(GTK_ORIENTATION_VERTICAL,0);gtk_container_add(GTK_CONTAINER(g->window),outer);
    GtkAccelGroup *accel=gtk_accel_group_new();gtk_window_add_accel_group(GTK_WINDOW(g->window),accel);
    g->menus=gtk_menu_bar_new();gtk_box_pack_start(GTK_BOX(outer),g->menus,FALSE,FALSE,0);
    GtkWidget *file=menu(g,g->menus,"_File"), *edit=menu(g,g->menus,"_Edit"), *view=menu(g,g->menus,"_View"),*help=menu(g,g->menus,"_Help");
    menu_item(g,file,"_New project…","new",accel,GDK_KEY_n,GDK_CONTROL_MASK);
    menu_item(g,file,"_Open…","open",accel,GDK_KEY_o,GDK_CONTROL_MASK);
    menu_item(g,file,"_Save","save",accel,GDK_KEY_s,GDK_CONTROL_MASK);
    menu_item(g,file,"Save _as…","save-as",accel,GDK_KEY_s,GDK_CONTROL_MASK|GDK_SHIFT_MASK);
    menu_item(g,file,"_Export locale source…","export",accel,0,0);
    menu_item(g,file,"_Compile to directory…","compile",accel,0,0);
    menu_item(g,file,"_Install and select…","install",accel,0,0);
    menu_item(g,file,"_Quit","quit",accel,GDK_KEY_q,GDK_CONTROL_MASK);
    g->undo=menu_item(g,edit,"_Undo","undo",accel,GDK_KEY_z,GDK_CONTROL_MASK);
    g->redo=menu_item(g,edit,"_Redo","redo",accel,GDK_KEY_z,GDK_CONTROL_MASK|GDK_SHIFT_MASK);
    menu_item(g,edit,"Choose _preset…","preset",accel,GDK_KEY_F7,0);
    menu_item(g,edit,"_Custom value…","custom",accel,GDK_KEY_F4,0);
    menu_item(g,edit,"Reset to _inherited","reset",accel,GDK_KEY_F8,0);
    menu_item(g,edit,"International _conventions…","international",accel,0,0);
    menu_item(g,edit,"Re_name locale…","rename",accel,0,0);
    menu_item(g,view,"Formatted _preview","preview",accel,GDK_KEY_F5,0);
    menu_item(g,view,"Generated _source","source",accel,GDK_KEY_F3,0);
    menu_item(g,view,"Sorting _words…","words",accel,0,0);
    menu_item(g,help,"_About / controls","help",accel,GDK_KEY_F1,0);
    menu_item(g,help,"Unicode data _license","license",accel,0,0);g_object_unref(accel);
    g->pane=gtk_paned_new(GTK_ORIENTATION_HORIZONTAL);gtk_box_pack_start(GTK_BOX(outer),g->pane,TRUE,TRUE,0);
    g->section_store=gtk_list_store_new(1,G_TYPE_STRING);g->sections=gtk_tree_view_new_with_model(GTK_TREE_MODEL(g->section_store));
    gtk_tree_view_set_headers_visible(GTK_TREE_VIEW(g->sections),FALSE);gtk_tree_view_append_column(GTK_TREE_VIEW(g->sections),gtk_tree_view_column_new_with_attributes("Section",gtk_cell_renderer_text_new(),"text",0,NULL));
    gtk_widget_set_name(g->sections,"locale-sections");atk_object_set_name(gtk_widget_get_accessible(g->sections),"Locale sections");
    GtkWidget *left=scrolled(g->sections);gtk_widget_set_size_request(left,195,-1);gtk_paned_pack1(GTK_PANED(g->pane),left,FALSE,FALSE);
    GtkWidget *right=gtk_box_new(GTK_ORIENTATION_VERTICAL,10);gtk_container_set_border_width(GTK_CONTAINER(right),12);gtk_paned_pack2(GTK_PANED(g->pane),right,TRUE,FALSE);
    g->heading=label("");gtk_box_pack_start(GTK_BOX(right),g->heading,FALSE,FALSE,0);
    GtkWidget *source_box=gtk_box_new(GTK_ORIENTATION_HORIZONTAL,10);g->source=label("");gtk_box_pack_start(GTK_BOX(source_box),g->source,TRUE,TRUE,0);button(g,source_box,"Change _inheritance…","inherit");gtk_box_pack_start(GTK_BOX(right),source_box,FALSE,FALSE,0);
    g->description=label("");gtk_box_pack_start(GTK_BOX(right),g->description,FALSE,FALSE,0);
    g->field_store=gtk_list_store_new(5,G_TYPE_STRING,G_TYPE_STRING,G_TYPE_STRING,G_TYPE_STRING,G_TYPE_STRING);g->fields=gtk_tree_view_new_with_model(GTK_TREE_MODEL(g->field_store));
    const char *titles[]={"Field","Definition","Formatted example","Value source"};
    for(int i=0;i<4;i++){GtkCellRenderer *r=gtk_cell_renderer_text_new();g_object_set(r,"ellipsize",PANGO_ELLIPSIZE_END,NULL);GtkTreeViewColumn *c=gtk_tree_view_column_new_with_attributes(titles[i],r,"text",i,NULL);gtk_tree_view_column_set_resizable(c,TRUE);gtk_tree_view_column_set_expand(c,i==2);gtk_tree_view_column_set_min_width(c,i==0?170:i==3?100:160);gtk_tree_view_column_set_max_width(c,i==1?280:600);gtk_tree_view_append_column(GTK_TREE_VIEW(g->fields),c);}
    gtk_tree_view_set_tooltip_column(GTK_TREE_VIEW(g->fields),4);gtk_widget_set_name(g->fields,"locale-fields");atk_object_set_name(gtk_widget_get_accessible(g->fields),"Locale fields");
    gtk_box_pack_start(GTK_BOX(right),scrolled(g->fields),TRUE,TRUE,0);
    GtkWidget *buttons=gtk_box_new(GTK_ORIENTATION_HORIZONTAL,8);button(g,buttons,"_Presets…","preset");button(g,buttons,"_Custom…","custom");button(g,buttons,"_Reset to inherited","reset");gtk_box_pack_start(GTK_BOX(right),buttons,FALSE,FALSE,0);
    g->help=label("Select a field, then choose a preset or edit a custom value.");gtk_box_pack_start(GTK_BOX(right),g->help,FALSE,FALSE,0);
    gtk_box_pack_start(GTK_BOX(right),label("Compiled locale preview"),FALSE,FALSE,0);
    g->examples=text_view();gtk_text_view_set_monospace(GTK_TEXT_VIEW(g->examples),TRUE);GtkWidget *examples=scrolled(g->examples);gtk_widget_set_size_request(examples,-1,165);gtk_box_pack_start(GTK_BOX(right),examples,FALSE,TRUE,0);
    GtkWidget *status_box=gtk_box_new(GTK_ORIENTATION_HORIZONTAL,8);gtk_container_set_border_width(GTK_CONTAINER(status_box),8);g->spinner=gtk_spinner_new();g->status=label("Loading locale…");gtk_box_pack_start(GTK_BOX(status_box),g->spinner,FALSE,FALSE,0);gtk_box_pack_start(GTK_BOX(status_box),g->status,TRUE,TRUE,0);gtk_box_pack_start(GTK_BOX(outer),status_box,FALSE,FALSE,0);
    g_signal_connect(gtk_tree_view_get_selection(GTK_TREE_VIEW(g->sections)),"changed",G_CALLBACK(section_changed),g);
    g_signal_connect(gtk_tree_view_get_selection(GTK_TREE_VIEW(g->fields)),"changed",G_CALLBACK(field_changed),g);
    g_signal_connect(g->fields,"row-activated",G_CALLBACK(field_activated),g);
    gtk_widget_show_all(g->window);emit(g,"ready",0,"");
}
LEGUI *legui_create(LEGUIEvent callback,void *context) {
    if(!gtk_init_check(NULL,NULL)) return NULL;
    LEGUI *g=g_new0(LEGUI,1);g->callback=callback;g->context=context;
    g->application=gtk_application_new("org.linuxlocaleeditor.Editor",G_APPLICATION_NON_UNIQUE);
    g_signal_connect(g->application,"activate",G_CALLBACK(activate),g);return g;
}
int legui_run(LEGUI *g) { char *args[]={"locale-editor",NULL}; return g_application_run(G_APPLICATION(g->application),1,args); }
void legui_quit(LEGUI *g) { g_application_quit(G_APPLICATION(g->application)); }
void legui_destroy(LEGUI *g) { for(GList *p=g->events;p;p=p->next){QueuedEvent *e=p->data;g_source_remove(e->source);}g_list_free(g->events);if(g->window)gtk_widget_destroy(g->window);if(g->section_store)g_object_unref(g->section_store);if(g->field_store)g_object_unref(g->field_store);g_object_unref(g->application);g_free(g); }
typedef struct {LEGUIIdle callback;void *context;} Idle;
static gboolean idle_run(gpointer data){Idle *i=data;i->callback(i->context);g_free(i);return G_SOURCE_REMOVE;}
void legui_idle(LEGUIIdle callback,void *context){Idle *i=g_new0(Idle,1);i->callback=callback;i->context=context;g_idle_add(idle_run,i);}
void legui_title(LEGUI *g,const char *title){gtk_window_set_title(GTK_WINDOW(g->window),title);}
void legui_section_add(LEGUI *g,const char *title){GtkTreeIter iter;gtk_list_store_append(g->section_store,&iter);gtk_list_store_set(g->section_store,&iter,0,title,-1);}
static void select_row(GtkWidget *tree,int index){if(index<0)return;GtkTreePath *p=gtk_tree_path_new_from_indices(index,-1);gtk_tree_selection_select_path(gtk_tree_view_get_selection(GTK_TREE_VIEW(tree)),p);gtk_tree_view_scroll_to_cell(GTK_TREE_VIEW(tree),p,NULL,FALSE,0,0);gtk_tree_path_free(p);}
void legui_section_select(LEGUI *g,int i){g->updating=TRUE;select_row(g->sections,i);g->updating=FALSE;}
void legui_heading(LEGUI *g,const char *title,const char *source,const char *description){gchar *escaped=g_markup_escape_text(title,-1),*markup=g_strdup_printf("<big><b>%s</b></big>",escaped);gtk_label_set_markup(GTK_LABEL(g->heading),markup);g_free(markup);g_free(escaped);gtk_label_set_text(GTK_LABEL(g->source),source);gtk_label_set_text(GTK_LABEL(g->description),description);}
void legui_fields_clear(LEGUI *g){g->updating=TRUE;gtk_list_store_clear(g->field_store);g->updating=FALSE;}
void legui_field_add(LEGUI *g,const char *label,const char *value,const char *example,const char *origin){GtkTreeIter iter;gtk_list_store_append(g->field_store,&iter);gchar *tooltip=g_markup_printf_escaped("%s\n%s\n%s",label,value,example);gtk_list_store_set(g->field_store,&iter,0,label,1,value,2,example,3,origin,4,tooltip,-1);g_free(tooltip);}
void legui_field_select(LEGUI *g,int i){g->updating=TRUE;select_row(g->fields,i);g->updating=FALSE;}
void legui_examples(LEGUI *g,const char *text){text_set(g->examples,text);}
void legui_status(LEGUI *g,const char *text){gtk_label_set_text(GTK_LABEL(g->status),text);}
void legui_help(LEGUI *g,const char *text){gtk_label_set_text(GTK_LABEL(g->help),text);}
void legui_busy(LEGUI *g,int busy){gtk_widget_set_sensitive(g->menus,!busy);gtk_widget_set_sensitive(g->pane,!busy);if(busy)gtk_spinner_start(GTK_SPINNER(g->spinner));else gtk_spinner_stop(GTK_SPINNER(g->spinner));}
void legui_history(LEGUI *g,int undo,int redo){gtk_widget_set_sensitive(g->undo,undo);gtk_widget_set_sensitive(g->redo,redo);}
static GtkWidget *body_dialog(LEGUI *g,const char *title,const char *text){GtkWidget *d=gtk_dialog_new_with_buttons(title,GTK_WINDOW(g->window),GTK_DIALOG_MODAL|GTK_DIALOG_DESTROY_WITH_PARENT,NULL,NULL);gtk_window_set_default_size(GTK_WINDOW(d),740,480);GtkWidget *v=text_view();text_set(v,text);GtkWidget *s=scrolled(v);gtk_container_set_border_width(GTK_CONTAINER(s),12);gtk_box_pack_start(GTK_BOX(gtk_dialog_get_content_area(GTK_DIALOG(d))),s,TRUE,TRUE,0);return d;}
void legui_message(LEGUI *g,const char *title,const char *text){GtkWidget *d=body_dialog(g,title,text);gtk_dialog_add_button(GTK_DIALOG(d),"_Close",GTK_RESPONSE_CLOSE);gtk_dialog_set_default_response(GTK_DIALOG(d),GTK_RESPONSE_CLOSE);gtk_widget_show_all(d);gtk_dialog_run(GTK_DIALOG(d));gtk_widget_destroy(d);}
int legui_confirm(LEGUI *g,const char *title,const char *text,const char *accept){GtkWidget *d=body_dialog(g,title,text);gtk_dialog_add_button(GTK_DIALOG(d),"_Cancel",GTK_RESPONSE_CANCEL);gtk_dialog_add_button(GTK_DIALOG(d),accept,GTK_RESPONSE_ACCEPT);gtk_dialog_set_default_response(GTK_DIALOG(d),GTK_RESPONSE_CANCEL);gtk_widget_show_all(d);int ok=gtk_dialog_run(GTK_DIALOG(d))==GTK_RESPONSE_ACCEPT;gtk_widget_destroy(d);return ok;}
char *legui_file(LEGUI *g,int mode,const char *title,const char *initial){GtkFileChooserAction action=mode==0?GTK_FILE_CHOOSER_ACTION_OPEN:mode==1?GTK_FILE_CHOOSER_ACTION_SAVE:GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER;GtkFileChooserNative *d=gtk_file_chooser_native_new(title,GTK_WINDOW(g->window),action,mode==0?"_Open":mode==1?"_Save":"_Choose","_Cancel");GtkFileChooser *c=GTK_FILE_CHOOSER(d);gtk_file_chooser_set_do_overwrite_confirmation(c,TRUE);if(initial&&*initial){if(mode==1){gchar *dir=g_path_get_dirname(initial),*base=g_path_get_basename(initial);gtk_file_chooser_set_current_folder(c,dir);gtk_file_chooser_set_current_name(c,base);g_free(dir);g_free(base);}else gtk_file_chooser_set_filename(c,initial);}char *result=gtk_native_dialog_run(GTK_NATIVE_DIALOG(d))==GTK_RESPONSE_ACCEPT?gtk_file_chooser_get_filename(c):NULL;g_object_unref(d);return result;}
static void prompt_changed(GtkEditable *entry,gpointer data){emit(data,"input-preview",0,gtk_entry_get_text(GTK_ENTRY(entry)));}
char *legui_prompt(LEGUI *g,const char *title,const char *initial,const char *help){GtkWidget *d=gtk_dialog_new_with_buttons(title,GTK_WINDOW(g->window),GTK_DIALOG_MODAL|GTK_DIALOG_DESTROY_WITH_PARENT,"_Cancel",GTK_RESPONSE_CANCEL,"_Apply",GTK_RESPONSE_ACCEPT,NULL);gtk_window_set_default_size(GTK_WINDOW(d),780,-1);GtkWidget *box=gtk_dialog_get_content_area(GTK_DIALOG(d));gtk_container_set_border_width(GTK_CONTAINER(box),16);gtk_box_set_spacing(GTK_BOX(box),12);GtkWidget *entry=gtk_entry_new();gtk_entry_set_text(GTK_ENTRY(entry),initial);gtk_entry_set_activates_default(GTK_ENTRY(entry),TRUE);gtk_box_pack_start(GTK_BOX(box),entry,FALSE,FALSE,0);gtk_box_pack_start(GTK_BOX(box),label(help),FALSE,FALSE,0);g->prompt_preview=label("");gtk_label_set_selectable(GTK_LABEL(g->prompt_preview),TRUE);gtk_box_pack_start(GTK_BOX(box),g->prompt_preview,FALSE,FALSE,0);g_signal_connect(entry,"changed",G_CALLBACK(prompt_changed),g);gtk_dialog_set_default_response(GTK_DIALOG(d),GTK_RESPONSE_ACCEPT);gtk_widget_show_all(d);gtk_widget_grab_focus(entry);gtk_editable_select_region(GTK_EDITABLE(entry),0,-1);emit(g,"input-preview",0,initial);char *result=gtk_dialog_run(GTK_DIALOG(d))==GTK_RESPONSE_ACCEPT?g_strdup(gtk_entry_get_text(GTK_ENTRY(entry))):NULL;g->prompt_preview=NULL;gtk_widget_destroy(d);return result;}
void legui_prompt_example(LEGUI *g,const char *text){if(g->prompt_preview)gtk_label_set_text(GTK_LABEL(g->prompt_preview),text);}
void legui_free(char *text){g_free(text);}

typedef struct {GtkWidget *dialog,*search,*tree,*preview;GtkListStore *store;GtkTreeModelFilter *filter;gchar *query;} Choices;
static gboolean choice_visible(GtkTreeModel *model,GtkTreeIter *iter,gpointer data){Choices *c=data;if(!c->query||!*c->query)return TRUE;gboolean found=FALSE;for(int i=0;i<4;i++){gchar *s=NULL;gtk_tree_model_get(model,iter,i,&s,-1);gchar *fold=g_utf8_casefold(s?s:"",-1);found|=strstr(fold,c->query)!=NULL;g_free(fold);g_free(s);}return found;}
static void choice_changed(GtkTreeSelection *sel,gpointer data){Choices *c=data;GtkTreeModel *m;GtkTreeIter i;if(gtk_tree_selection_get_selected(sel,&m,&i)){gchar *value,*detail;gtk_tree_model_get(m,&i,2,&value,3,&detail,-1);gchar *text=g_strconcat(value,"\n\n",detail,NULL);text_set(c->preview,text);g_free(value);g_free(detail);g_free(text);}else text_set(c->preview,"");}
static void choice_search(GtkEditable *entry,gpointer data){Choices *c=data;g_free(c->query);c->query=g_utf8_casefold(gtk_entry_get_text(GTK_ENTRY(entry)),-1);gtk_tree_model_filter_refilter(c->filter);select_row(c->tree,0);}
static void choice_activated(GtkTreeView *tree,GtkTreePath *p,GtkTreeViewColumn *col,gpointer data){(void)tree;(void)p;(void)col;Choices *c=data;gtk_dialog_response(GTK_DIALOG(c->dialog),GTK_RESPONSE_ACCEPT);}
void *legui_choices(LEGUI *g,const char *title,int custom){Choices *c=g_new0(Choices,1);c->dialog=gtk_dialog_new_with_buttons(title,GTK_WINDOW(g->window),GTK_DIALOG_MODAL|GTK_DIALOG_DESTROY_WITH_PARENT,"_Cancel",GTK_RESPONSE_CANCEL,NULL);if(custom)gtk_dialog_add_button(GTK_DIALOG(c->dialog),"Cu_stom…",1001);gtk_dialog_add_button(GTK_DIALOG(c->dialog),"_Apply",GTK_RESPONSE_ACCEPT);gtk_dialog_set_default_response(GTK_DIALOG(c->dialog),GTK_RESPONSE_ACCEPT);gtk_window_set_default_size(GTK_WINDOW(c->dialog),960,600);GtkWidget *box=gtk_dialog_get_content_area(GTK_DIALOG(c->dialog));gtk_container_set_border_width(GTK_CONTAINER(box),12);gtk_box_set_spacing(GTK_BOX(box),10);c->search=gtk_search_entry_new();gtk_entry_set_activates_default(GTK_ENTRY(c->search),TRUE);gtk_entry_set_placeholder_text(GTK_ENTRY(c->search),"Search definitions, examples and source locales");gtk_box_pack_start(GTK_BOX(box),c->search,FALSE,FALSE,0);c->store=gtk_list_store_new(4,G_TYPE_STRING,G_TYPE_STRING,G_TYPE_STRING,G_TYPE_STRING);c->filter=GTK_TREE_MODEL_FILTER(gtk_tree_model_filter_new(GTK_TREE_MODEL(c->store),NULL));gtk_tree_model_filter_set_visible_func(c->filter,choice_visible,c,NULL);c->tree=gtk_tree_view_new_with_model(GTK_TREE_MODEL(c->filter));for(int n=1;n<3;n++){GtkCellRenderer *r=gtk_cell_renderer_text_new();g_object_set(r,"ellipsize",PANGO_ELLIPSIZE_END,NULL);GtkTreeViewColumn *column=gtk_tree_view_column_new_with_attributes(n==1?"Definition / preset":"Formatted example",r,"text",n,NULL);gtk_tree_view_column_set_expand(column,TRUE);gtk_tree_view_column_set_resizable(column,TRUE);gtk_tree_view_column_set_min_width(column,320);gtk_tree_view_append_column(GTK_TREE_VIEW(c->tree),column);}gtk_box_pack_start(GTK_BOX(box),scrolled(c->tree),TRUE,TRUE,0);c->preview=text_view();GtkWidget *s=scrolled(c->preview);gtk_widget_set_size_request(s,-1,140);gtk_box_pack_start(GTK_BOX(box),s,FALSE,TRUE,0);g_signal_connect(c->search,"changed",G_CALLBACK(choice_search),c);g_signal_connect(gtk_tree_view_get_selection(GTK_TREE_VIEW(c->tree)),"changed",G_CALLBACK(choice_changed),c);g_signal_connect(c->tree,"row-activated",G_CALLBACK(choice_activated),c);return c;}
void legui_choice_add(void *data,const char *id,const char *name,const char *example,const char *detail){Choices *c=data;GtkTreeIter i;gtk_list_store_append(c->store,&i);gtk_list_store_set(c->store,&i,0,id,1,name,2,example,3,detail,-1);}
char *legui_choice_run(void *data,const char *initial){Choices *c=data;gtk_widget_show_all(c->dialog);int selected=0,index=0;GtkTreeIter i;gboolean valid=gtk_tree_model_get_iter_first(GTK_TREE_MODEL(c->store),&i);while(valid){gchar *id;gtk_tree_model_get(GTK_TREE_MODEL(c->store),&i,0,&id,-1);if(g_strcmp0(id,initial)==0)selected=index;g_free(id);index++;valid=gtk_tree_model_iter_next(GTK_TREE_MODEL(c->store),&i);}select_row(c->tree,selected);gtk_widget_grab_focus(c->search);int response=gtk_dialog_run(GTK_DIALOG(c->dialog));gchar *result=NULL;if(response==1001)result=g_strdup("__custom__");else if(response==GTK_RESPONSE_ACCEPT){GtkTreeModel *model;if(gtk_tree_selection_get_selected(gtk_tree_view_get_selection(GTK_TREE_VIEW(c->tree)),&model,&i))gtk_tree_model_get(model,&i,0,&result,-1);}gtk_widget_destroy(c->dialog);g_object_unref(c->filter);g_object_unref(c->store);g_free(c->query);g_free(c);return result;}
