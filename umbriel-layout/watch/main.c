#define _POSIX_C_SOURCE 200809L

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wayland-client.h>

#include "ext-workspace-v1-client-protocol.h"

struct output {
  struct wl_output *wl;
  char *name;
  struct output *next;
};

struct group {
  struct ext_workspace_group_handle_v1 *handle;
  struct output *output;
  char *emitted;
  struct group *next;
};

struct workspace {
  struct ext_workspace_handle_v1 *handle;
  struct group *group;
  char *name;
  bool active;
  struct workspace *next;
};

static struct wl_display *display;
static struct ext_workspace_manager_v1 *manager;
static struct output *outputs;
static struct group *groups;
static struct workspace *workspaces;
static bool ready;

static char *dup_or_null(const char *value) {
  if (value == NULL) {
    return NULL;
  }
  char *copy = strdup(value);
  if (copy == NULL) {
    fprintf(stderr, "umbriel-workspace-watch: out of memory\n");
    exit(1);
  }
  return copy;
}

static void output_geometry(void *data, struct wl_output *wl, int32_t x,
                            int32_t y, int32_t pw, int32_t ph, int32_t subpixel,
                            const char *make, const char *model,
                            int32_t transform) {
  (void)data;
  (void)wl;
  (void)x;
  (void)y;
  (void)pw;
  (void)ph;
  (void)subpixel;
  (void)make;
  (void)model;
  (void)transform;
}

static void output_mode(void *data, struct wl_output *wl, uint32_t flags,
                        int32_t w, int32_t h, int32_t refresh) {
  (void)data;
  (void)wl;
  (void)flags;
  (void)w;
  (void)h;
  (void)refresh;
}

static void output_done(void *data, struct wl_output *wl) {
  (void)data;
  (void)wl;
}

static void output_scale(void *data, struct wl_output *wl, int32_t factor) {
  (void)data;
  (void)wl;
  (void)factor;
}

static void output_name(void *data, struct wl_output *wl, const char *name) {
  (void)wl;
  struct output *out = data;
  free(out->name);
  out->name = dup_or_null(name);
}

static void output_description(void *data, struct wl_output *wl,
                               const char *description) {
  (void)data;
  (void)wl;
  (void)description;
}

static const struct wl_output_listener output_listener = {
    .geometry = output_geometry,
    .mode = output_mode,
    .done = output_done,
    .scale = output_scale,
    .name = output_name,
    .description = output_description,
};

static struct output *find_output(struct wl_output *wl) {
  for (struct output *out = outputs; out != NULL; out = out->next) {
    if (out->wl == wl) {
      return out;
    }
  }
  return NULL;
}

static struct workspace *
find_workspace(struct ext_workspace_handle_v1 *handle) {
  for (struct workspace *ws = workspaces; ws != NULL; ws = ws->next) {
    if (ws->handle == handle) {
      return ws;
    }
  }
  return NULL;
}

static void workspace_id(void *data, struct ext_workspace_handle_v1 *handle,
                         const char *id) {
  (void)data;
  (void)handle;
  (void)id;
}

static void workspace_name(void *data, struct ext_workspace_handle_v1 *handle,
                           const char *name) {
  (void)handle;
  struct workspace *ws = data;
  free(ws->name);
  ws->name = dup_or_null(name);
}

static void workspace_coordinates(void *data,
                                  struct ext_workspace_handle_v1 *handle,
                                  struct wl_array *coordinates) {
  (void)data;
  (void)handle;
  (void)coordinates;
}

static void workspace_state(void *data, struct ext_workspace_handle_v1 *handle,
                            uint32_t state) {
  (void)handle;
  struct workspace *ws = data;
  ws->active = (state & EXT_WORKSPACE_HANDLE_V1_STATE_ACTIVE) != 0;
}

static void workspace_capabilities(void *data,
                                   struct ext_workspace_handle_v1 *handle,
                                   uint32_t capabilities) {
  (void)data;
  (void)handle;
  (void)capabilities;
}

static void workspace_removed(void *data,
                              struct ext_workspace_handle_v1 *handle) {
  struct workspace *target = data;
  struct workspace **link = &workspaces;
  while (*link != NULL) {
    if (*link == target) {
      *link = target->next;
      break;
    }
    link = &(*link)->next;
  }
  ext_workspace_handle_v1_destroy(handle);
  free(target->name);
  free(target);
}

static const struct ext_workspace_handle_v1_listener workspace_listener = {
    .id = workspace_id,
    .name = workspace_name,
    .coordinates = workspace_coordinates,
    .state = workspace_state,
    .capabilities = workspace_capabilities,
    .removed = workspace_removed,
};

static void group_capabilities(void *data,
                               struct ext_workspace_group_handle_v1 *handle,
                               uint32_t capabilities) {
  (void)data;
  (void)handle;
  (void)capabilities;
}

static void group_output_enter(void *data,
                               struct ext_workspace_group_handle_v1 *handle,
                               struct wl_output *wl) {
  (void)handle;
  struct group *group = data;
  group->output = find_output(wl);
}

static void group_output_leave(void *data,
                               struct ext_workspace_group_handle_v1 *handle,
                               struct wl_output *wl) {
  (void)handle;
  (void)wl;
  struct group *group = data;
  group->output = NULL;
}

static void group_workspace_enter(void *data,
                                  struct ext_workspace_group_handle_v1 *handle,
                                  struct ext_workspace_handle_v1 *handle_ws) {
  (void)handle;
  struct group *group = data;
  struct workspace *ws = find_workspace(handle_ws);
  if (ws != NULL) {
    ws->group = group;
  }
}

static void group_workspace_leave(void *data,
                                  struct ext_workspace_group_handle_v1 *handle,
                                  struct ext_workspace_handle_v1 *handle_ws) {
  (void)data;
  (void)handle;
  struct workspace *ws = find_workspace(handle_ws);
  if (ws != NULL) {
    ws->group = NULL;
  }
}

static void group_removed(void *data,
                          struct ext_workspace_group_handle_v1 *handle) {
  struct group *target = data;
  for (struct workspace *ws = workspaces; ws != NULL; ws = ws->next) {
    if (ws->group == target) {
      ws->group = NULL;
    }
  }
  struct group **link = &groups;
  while (*link != NULL) {
    if (*link == target) {
      *link = target->next;
      break;
    }
    link = &(*link)->next;
  }
  ext_workspace_group_handle_v1_destroy(handle);
  free(target->emitted);
  free(target);
}

static const struct ext_workspace_group_handle_v1_listener group_listener = {
    .capabilities = group_capabilities,
    .output_enter = group_output_enter,
    .output_leave = group_output_leave,
    .workspace_enter = group_workspace_enter,
    .workspace_leave = group_workspace_leave,
    .removed = group_removed,
};

static void
manager_workspace_group(void *data, struct ext_workspace_manager_v1 *mgr,
                        struct ext_workspace_group_handle_v1 *handle) {
  (void)data;
  (void)mgr;
  struct group *group = calloc(1, sizeof(*group));
  if (group == NULL) {
    fprintf(stderr, "umbriel-workspace-watch: out of memory\n");
    exit(1);
  }
  group->handle = handle;
  group->next = groups;
  groups = group;
  ext_workspace_group_handle_v1_add_listener(handle, &group_listener, group);
}

static void manager_workspace(void *data, struct ext_workspace_manager_v1 *mgr,
                              struct ext_workspace_handle_v1 *handle) {
  (void)data;
  (void)mgr;
  struct workspace *ws = calloc(1, sizeof(*ws));
  if (ws == NULL) {
    fprintf(stderr, "umbriel-workspace-watch: out of memory\n");
    exit(1);
  }
  ws->handle = handle;
  ws->next = workspaces;
  workspaces = ws;
  ext_workspace_handle_v1_add_listener(handle, &workspace_listener, ws);
}

static void emit_changes(void) {
  for (struct group *group = groups; group != NULL; group = group->next) {
    const char *ws_name = NULL;
    for (struct workspace *ws = workspaces; ws != NULL; ws = ws->next) {
      if (ws->group == group && ws->active && ws->name != NULL) {
        ws_name = ws->name;
        break;
      }
    }
    if (ws_name == NULL) {
      continue;
    }
    const char *out_name =
        (group->output != NULL && group->output->name != NULL)
            ? group->output->name
            : "?";

    char line[512];
    snprintf(line, sizeof(line), "%s %s", out_name, ws_name);
    if (group->emitted != NULL && strcmp(group->emitted, line) == 0) {
      continue;
    }
    free(group->emitted);
    group->emitted = dup_or_null(line);
    printf("%s\n", line);
    fflush(stdout);
  }
}

static void manager_done(void *data, struct ext_workspace_manager_v1 *mgr) {
  (void)data;
  (void)mgr;
  if (!ready) {
    return;
  }
  emit_changes();
}

static void manager_finished(void *data, struct ext_workspace_manager_v1 *mgr) {
  (void)data;
  ext_workspace_manager_v1_destroy(mgr);
  manager = NULL;
}

static const struct ext_workspace_manager_v1_listener manager_listener = {
    .workspace_group = manager_workspace_group,
    .workspace = manager_workspace,
    .done = manager_done,
    .finished = manager_finished,
};

static void registry_global(void *data, struct wl_registry *registry,
                            uint32_t name, const char *interface,
                            uint32_t version) {
  (void)data;
  if (strcmp(interface, ext_workspace_manager_v1_interface.name) == 0) {
    manager = wl_registry_bind(registry, name,
                               &ext_workspace_manager_v1_interface, 1);
    ext_workspace_manager_v1_add_listener(manager, &manager_listener, NULL);
    return;
  }
  if (strcmp(interface, wl_output_interface.name) == 0) {
    // Version 4 is where wl_output reports its connector name
    if (version < 4) {
      return;
    }
    struct output *out = calloc(1, sizeof(*out));
    if (out == NULL) {
      fprintf(stderr, "umbriel-workspace-watch: out of memory\n");
      exit(1);
    }
    out->wl = wl_registry_bind(registry, name, &wl_output_interface, 4);
    out->next = outputs;
    outputs = out;
    wl_output_add_listener(out->wl, &output_listener, out);
  }
}

static void registry_global_remove(void *data, struct wl_registry *registry,
                                   uint32_t name) {
  (void)data;
  (void)registry;
  (void)name;
}

static const struct wl_registry_listener registry_listener = {
    .global = registry_global,
    .global_remove = registry_global_remove,
};

int main(void) {
  display = wl_display_connect(NULL);
  if (display == NULL) {
    fprintf(stderr,
            "umbriel-workspace-watch: cannot connect to the Wayland display\n");
    return 1;
  }

  struct wl_registry *registry = wl_display_get_registry(display);
  wl_registry_add_listener(registry, &registry_listener, NULL);
  wl_display_roundtrip(display);

  if (manager == NULL) {
    fprintf(stderr, "umbriel-workspace-watch: compositor does not support "
                    "ext-workspace-v1\n");
    return 1;
  }

  wl_display_roundtrip(display);

  ready = true;
  emit_changes();

  while (wl_display_dispatch(display) != -1) {
    if (manager == NULL) {
      break;
    }
  }

  return 0;
}
