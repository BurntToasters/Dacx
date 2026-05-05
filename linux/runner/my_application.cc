#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include <stdio.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>

#include "flutter/generated_plugin_registrant.h"

static const char kOpenFileMethodChannel[] = "run.rosie.dacx/open_file/methods";
static const char kOpenFileEventChannel[] = "run.rosie.dacx/open_file/events";
static const char kNewInstanceFlag[] = "--new-instance";

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* window;
  FlView* view;
  FlMethodChannel* open_file_method_channel;
  FlEventChannel* open_file_event_channel;
  GPtrArray* pending_open_files;
  gboolean event_listener_active;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static gchar* dacx_resolve_flag_file_path() {
  const gchar* xdg = g_getenv("XDG_CONFIG_HOME");
  if (xdg != nullptr && *xdg != '\0') {
    return g_build_filename(xdg, "dacx", "allow_multi_instance", nullptr);
  }
  const gchar* home = g_getenv("HOME");
  if (home == nullptr || *home == '\0') return nullptr;
  return g_build_filename(home, ".config", "dacx", "allow_multi_instance",
                          nullptr);
}

static gboolean dacx_allow_multiple_instances_enabled() {
  g_autofree gchar* path = dacx_resolve_flag_file_path();
  if (path == nullptr) return FALSE;
  return g_file_test(path, G_FILE_TEST_EXISTS);
}

static gboolean dacx_proc_args_request_new_instance() {
  FILE* cmdline = fopen("/proc/self/cmdline", "rb");
  if (cmdline == nullptr) return FALSE;
  char buf[8192];
  size_t read = fread(buf, 1, sizeof(buf) - 1, cmdline);
  fclose(cmdline);
  buf[read] = '\0';
  size_t i = 0;
  while (i < read) {
    const char* arg = buf + i;
    size_t len = strlen(arg);
    if (g_strcmp0(arg, kNewInstanceFlag) == 0) return TRUE;
    i += len + 1;
  }
  return FALSE;
}

static char** dacx_strip_new_instance_flag(char** argv) {
  GPtrArray* out = g_ptr_array_new();
  if (argv != nullptr) {
    for (int i = 0; argv[i] != nullptr; i++) {
      if (g_strcmp0(argv[i], kNewInstanceFlag) == 0) continue;
      g_ptr_array_add(out, g_strdup(argv[i]));
    }
  }
  g_ptr_array_add(out, nullptr);
  return (char**)g_ptr_array_free(out, FALSE);
}

static void dacx_dispatch_pending_to_dart(MyApplication* self) {
  if (self->pending_open_files == nullptr ||
      self->pending_open_files->len == 0) {
    return;
  }
  if (!self->event_listener_active ||
      self->open_file_event_channel == nullptr) {
    return;
  }
  for (guint i = 0; i < self->pending_open_files->len; i++) {
    const gchar* path =
        (const gchar*)g_ptr_array_index(self->pending_open_files, i);
    g_autoptr(FlValue) value = fl_value_new_string(path);
    fl_event_channel_send(self->open_file_event_channel, value, nullptr,
                          nullptr);
  }
  g_ptr_array_set_size(self->pending_open_files, 0);
}

static void dacx_handle_open_path(MyApplication* self, const gchar* path) {
  if (path == nullptr || *path == '\0') return;
  if (self->pending_open_files == nullptr) {
    self->pending_open_files =
        g_ptr_array_new_with_free_func((GDestroyNotify)g_free);
  }
  if (self->event_listener_active &&
      self->open_file_event_channel != nullptr) {
    g_autoptr(FlValue) value = fl_value_new_string(path);
    fl_event_channel_send(self->open_file_event_channel, value, nullptr,
                          nullptr);
  } else {
    g_ptr_array_add(self->pending_open_files, g_strdup(path));
  }
}

static void dacx_method_call_cb(FlMethodChannel* channel, FlMethodCall* call,
                                gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(call);
  if (g_strcmp0(method, "getPendingFiles") == 0) {
    g_autoptr(FlValue) list = fl_value_new_list();
    if (self->pending_open_files != nullptr) {
      for (guint i = 0; i < self->pending_open_files->len; i++) {
        const gchar* path =
            (const gchar*)g_ptr_array_index(self->pending_open_files, i);
        fl_value_append_take(list, fl_value_new_string(path));
      }
      g_ptr_array_set_size(self->pending_open_files, 0);
    }
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_success_response_new(list));
    fl_method_call_respond(call, response, nullptr);
    return;
  }
  g_autoptr(FlMethodResponse) not_implemented =
      FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  fl_method_call_respond(call, not_implemented, nullptr);
}

static FlMethodErrorResponse* dacx_event_listen_cb(FlEventChannel* channel,
                                                   FlValue* args,
                                                   gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  self->event_listener_active = TRUE;
  dacx_dispatch_pending_to_dart(self);
  return nullptr;
}

static FlMethodErrorResponse* dacx_event_cancel_cb(FlEventChannel* channel,
                                                   FlValue* args,
                                                   gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  self->event_listener_active = FALSE;
  return nullptr;
}

static void dacx_setup_channels(MyApplication* self) {
  if (self->view == nullptr) return;
  if (self->open_file_method_channel != nullptr) return;

  FlEngine* engine = fl_view_get_engine(self->view);
  FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(engine);
  g_autoptr(FlStandardMethodCodec) method_codec =
      fl_standard_method_codec_new();
  self->open_file_method_channel = fl_method_channel_new(
      messenger, kOpenFileMethodChannel, FL_METHOD_CODEC(method_codec));
  fl_method_channel_set_method_call_handler(
      self->open_file_method_channel, dacx_method_call_cb, self, nullptr);

  g_autoptr(FlStandardMethodCodec) event_codec =
      fl_standard_method_codec_new();
  self->open_file_event_channel = fl_event_channel_new(
      messenger, kOpenFileEventChannel, FL_METHOD_CODEC(event_codec));
  fl_event_channel_set_stream_handlers(self->open_file_event_channel,
                                       dacx_event_listen_cb,
                                       dacx_event_cancel_cb, self, nullptr);
}

static GtkWindow* my_application_create_window(MyApplication* self,
                                               GApplication* application) {
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "Dacx");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Dacx");
  }

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  gdk_rgba_parse(&background_color, "#00000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));

  self->window = window;
  self->view = view;
  dacx_setup_channels(self);
  return window;
}

static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  if (self->window != nullptr) {
    gtk_window_present(self->window);
    return;
  }
  GtkWindow* window = my_application_create_window(self, application);
  gtk_window_present(window);
}

static void my_application_open(GApplication* application, GFile** files,
                                gint n_files, const gchar* /*hint*/) {
  MyApplication* self = MY_APPLICATION(application);

  if (self->window == nullptr) {
    if (n_files > 0 && files != nullptr) {
      g_autofree gchar* path = g_file_get_path(files[0]);
      if (path != nullptr) {
        g_strfreev(self->dart_entrypoint_arguments);
        self->dart_entrypoint_arguments = g_new0(char*, 2);
        self->dart_entrypoint_arguments[0] = g_strdup(path);
        self->dart_entrypoint_arguments[1] = nullptr;
      }
    }
    GtkWindow* window = my_application_create_window(self, application);
    gtk_window_present(window);
    return;
  }

  for (gint i = 0; i < n_files; i++) {
    if (files[i] == nullptr) continue;
    g_autofree gchar* path = g_file_get_path(files[i]);
    if (path != nullptr) {
      dacx_handle_open_path(self, path);
    }
  }
  gtk_window_present(self->window);
}

static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);

  gint argc = g_strv_length(*arguments);
  if (argc > 1024) {
    g_warning("dacx: refusing to forward %d CLI arguments (cap is 1024)", argc);
    *exit_status = 1;
    return TRUE;
  }
  self->dart_entrypoint_arguments =
      dacx_strip_new_instance_flag(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

static void my_application_startup(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

static void my_application_shutdown(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->open_file_method_channel);
  g_clear_object(&self->open_file_event_channel);
  if (self->pending_open_files != nullptr) {
    g_ptr_array_free(self->pending_open_files, TRUE);
    self->pending_open_files = nullptr;
  }
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->open = my_application_open;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  self->pending_open_files =
      g_ptr_array_new_with_free_func((GDestroyNotify)g_free);
}

MyApplication* my_application_new() {
  g_set_prgname(APPLICATION_ID);

  // Pick a unique application-id when the user has opted in to multi-instance
  // mode or launched with --new-instance, so GApplication does not collapse
  // this process into the already-running primary instance via D-Bus.
  gboolean force_unique = dacx_allow_multiple_instances_enabled() ||
                          dacx_proc_args_request_new_instance();

  g_autofree gchar* unique_id =
      force_unique
          ? g_strdup_printf("%s.n%d", APPLICATION_ID, (int)getpid())
          : g_strdup(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(
      my_application_get_type(), "application-id", unique_id, "flags",
      G_APPLICATION_HANDLES_OPEN, nullptr));
}
