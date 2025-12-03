#define _POSIX_C_SOURCE 200809L

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <stdint.h>

#include "yyjson.h"

#define SKILLSFS_VERSION "0.1.0"

static void safe_localtime(const time_t *timer, struct tm *out_tm) {
#if defined(_WIN32)
    localtime_s(out_tm, timer);
#else
    localtime_r(timer, out_tm);
#endif
}

typedef struct {
    char *skill_name;
    char *metadata;
    char *instructions;
    char *last_params;
    char *last_result;
    char *status_json;
    char *log_text;
    size_t log_len;
    size_t log_cap;
    time_t last_request_ts;
    time_t last_exec_ts;
    double last_duration_ms;
    int cache_ttl_seconds;
    int pending;
    int initialized;
} SkillFS;

typedef struct {
    const char *Name;
    int64_t Size;
    uint32_t Mode;
    int64_t ModTime;
    int32_t IsDir;
    const char *MetaName;
    const char *MetaType;
    const char *MetaContent;
} FileInfoC;

typedef struct {
    FileInfoC *Items;
    int Count;
} FileInfoArray;

/*------------------------- Utilities --------------------------------*/
static char *dup_string(const char *src) {
    if (!src) return NULL;
    size_t len = strlen(src);
    char *copy = (char *)malloc(len + 1);
    if (!copy) return NULL;
    memcpy(copy, src, len);
    copy[len] = '\0';
    return copy;
}

static void free_string(char **ptr) {
    if (*ptr) {
        free(*ptr);
        *ptr = NULL;
    }
}

static int append_text(char **buffer, size_t *len, size_t *cap, const char *text) {
    size_t text_len = strlen(text);
    if (*len + text_len + 1 > *cap) {
        size_t new_cap = (*cap == 0) ? 1024 : *cap * 2;
        while (new_cap < *len + text_len + 1) new_cap *= 2;
        char *tmp = (char *)realloc(*buffer, new_cap);
        if (!tmp) return 0;
        *buffer = tmp;
        *cap = new_cap;
    }
    memcpy(*buffer + *len, text, text_len);
    *len += text_len;
    (*buffer)[*len] = '\0';
    return 1;
}

static char *json_escape(const char *text) {
    if (!text) return dup_string("");
    size_t len = 0, cap = strlen(text) + 16;
    char *out = (char *)malloc(cap);
    if (!out) return NULL;
    out[0] = '\0';
    for (const char *p = text; *p; ++p) {
        char buf[8];
        switch (*p) {
            case '\\': strcpy(buf, "\\\\"); break;
            case '"': strcpy(buf, "\\\""); break;
            case '\n': strcpy(buf, "\\n"); break;
            case '\r': strcpy(buf, "\\r"); break;
            case '\t': strcpy(buf, "\\t"); break;
            default:
                buf[0] = *p;
                buf[1] = '\0';
                break;
        }
        size_t need = strlen(buf);
        if (len + need + 1 > cap) {
            cap *= 2;
            char *tmp = (char *)realloc(out, cap);
            if (!tmp) {
                free(out);
                return NULL;
            }
            out = tmp;
        }
        strcpy(out + len, buf);
        len += need;
    }
    return out;
}

static void append_log(SkillFS *fs, const char *level, const char *message) {
    time_t now = time(NULL);
    struct tm tm_now;
    safe_localtime(&now, &tm_now);
    char ts[32];
    strftime(ts, sizeof(ts), "%Y-%m-%d %H:%M:%S", &tm_now);
    char line[1024];
    snprintf(line, sizeof(line), "[%s] [%s] %s\n", ts, level, message ? message : "");
    append_text(&fs->log_text, &fs->log_len, &fs->log_cap, line);
}

static void set_status(SkillFS *fs, const char *state, int cache_hit) {
    char ts_buf[64] = "";
    if (fs->last_exec_ts > 0) {
        struct tm tm_last;
        safe_localtime(&fs->last_exec_ts, &tm_last);
        strftime(ts_buf, sizeof(ts_buf), "%Y-%m-%d %H:%M:%S", &tm_last);
    }
    char *skill_json = json_escape(fs->skill_name ? fs->skill_name : "skillfs");
    if (!skill_json) return;
    char status_buf[512];
    snprintf(status_buf, sizeof(status_buf),
             "{\"skill\":\"%s\",\"state\":\"%s\",\"pending\":%s,"
             "\"cache_hit\":%s,\"last_execution\":\"%s\",\"duration_ms\":%.2f}",
             skill_json,
             state,
             fs->pending ? "true" : "false",
             cache_hit ? "true" : "false",
             ts_buf,
             fs->last_duration_ms);
    free_string(&fs->status_json);
    fs->status_json = dup_string(status_buf);
    free(skill_json);
}

static const char *run_skill(SkillFS *fs) {
    if (!fs->last_params || strlen(fs->last_params) == 0) {
        return "no execution payload";
    }
    set_status(fs, "running", 0);
    append_log(fs, "INFO", "Executing skill payload");
    clock_t start = clock();

    time_t now = time(NULL);
    struct tm tm_now;
    safe_localtime(&now, &tm_now);
    char ts[64];
    strftime(ts, sizeof(ts), "%Y-%m-%d %H:%M:%S", &tm_now);

    const char *skill = fs->skill_name ? fs->skill_name : "skillfs";
    const char *instr = fs->instructions ? fs->instructions : "No instructions provided.";

    size_t needed = strlen(skill) + strlen(instr) + strlen(fs->last_params) + 512;
    char *result = (char *)malloc(needed);
    if (!result) {
        set_status(fs, "failed", 0);
        append_log(fs, "ERROR", "Allocation failure while building result");
        return "allocation failure";
    }
    snprintf(result, needed,
             "Skill: %s\n"
             "Executed at: %s\n\n"
             "Instructions:\n%s\n\n"
             "Parameters:\n%s\n\n"
             "Notes:\nThis is a placeholder execution for the SkillsFS MVP.\n",
             skill, ts, instr, fs->last_params);

    free_string(&fs->last_result);
    fs->last_result = result;
    fs->last_exec_ts = now;
    fs->last_duration_ms = ((double)(clock() - start) / CLOCKS_PER_SEC) * 1000.0;
    fs->pending = 0;

    set_status(fs, "completed", 0);
    append_log(fs, "INFO", "Skill execution completed");
    return NULL;
}

static const char *ensure_result_current(SkillFS *fs, int *out_cache_hit) {
    if (out_cache_hit) *out_cache_hit = 0;
    if (!fs->last_params || strlen(fs->last_params) == 0) {
        return "No execution payload yet. Write to /execute first.\n";
    }
    int use_cache = (!fs->pending && fs->last_result != NULL);
    if (use_cache && fs->cache_ttl_seconds > 0 && fs->last_exec_ts > 0) {
        double age = difftime(time(NULL), fs->last_exec_ts);
        if (age > fs->cache_ttl_seconds) {
            use_cache = 0;
        }
    }
    if (use_cache) {
        set_status(fs, "completed", 1);
        append_log(fs, "DEBUG", "Cache hit for /result");
        if (out_cache_hit) *out_cache_hit = 1;
        return NULL;
    }
    return run_skill(fs);
}

/*------------------------- Plugin lifecycle -------------------------*/
void* PluginNew() {
    SkillFS *fs = (SkillFS *)calloc(1, sizeof(SkillFS));
    if (!fs) return NULL;
    fs->cache_ttl_seconds = 3600;
    fs->skill_name = dup_string("skillfs-mvp");
    fs->instructions = dup_string("Describe how to process incoming payloads.");
    fs->metadata = dup_string("owner=unknown");
    set_status(fs, "idle", 0);
    append_log(fs, "INFO", "SkillsFS plugin created");
    return fs;
}

void PluginFree(void* plugin) {
    if (!plugin) return;
    SkillFS *fs = (SkillFS *)plugin;
    free_string(&fs->skill_name);
    free_string(&fs->metadata);
    free_string(&fs->instructions);
    free_string(&fs->last_params);
    free_string(&fs->last_result);
    free_string(&fs->status_json);
    free_string(&fs->log_text);
    free(fs);
}

const char* PluginName(void* plugin) {
    (void)plugin;
    return "skillsfs";
}

static const char *apply_config(SkillFS *fs, const char *config_json) {
    if (!config_json || strlen(config_json) == 0) return NULL;
    yyjson_doc *doc = yyjson_read(config_json, strlen(config_json), 0);
    if (!doc) return "invalid config json";
    yyjson_val *root = yyjson_doc_get_root(doc);

    yyjson_val *name_val = yyjson_obj_get(root, "skill_name");
    yyjson_val *meta_val = yyjson_obj_get(root, "metadata");
    yyjson_val *instr_val = yyjson_obj_get(root, "instructions");
    yyjson_val *ttl_val = yyjson_obj_get(root, "cache_ttl_seconds");

    if (name_val && yyjson_is_str(name_val)) {
        free_string(&fs->skill_name);
        fs->skill_name = dup_string(yyjson_get_str(name_val));
    }
    if (meta_val && yyjson_is_str(meta_val)) {
        free_string(&fs->metadata);
        fs->metadata = dup_string(yyjson_get_str(meta_val));
    }
    if (instr_val && yyjson_is_str(instr_val)) {
        free_string(&fs->instructions);
        fs->instructions = dup_string(yyjson_get_str(instr_val));
    }
    if (ttl_val && yyjson_is_int(ttl_val)) {
        fs->cache_ttl_seconds = (int)yyjson_get_int(ttl_val);
        if (fs->cache_ttl_seconds < 0) fs->cache_ttl_seconds = 0;
    }

    yyjson_doc_free(doc);
    return NULL;
}

const char* PluginValidate(void* plugin, const char* config_json) {
    (void)plugin;
    (void)config_json;
    return NULL;
}

const char* PluginInitialize(void* plugin, const char* config_json) {
    SkillFS *fs = (SkillFS *)plugin;
    if (!fs) return "plugin is null";
    const char *err = apply_config(fs, config_json);
    if (err) return err;
    fs->initialized = 1;
    append_log(fs, "INFO", "SkillsFS initialized");
    set_status(fs, "idle", 0);
    return NULL;
}

const char* PluginShutdown(void* plugin) {
    SkillFS *fs = (SkillFS *)plugin;
    if (!fs) return "plugin is null";
    fs->initialized = 0;
    append_log(fs, "INFO", "SkillsFS shutdown");
    return NULL;
}

const char* PluginGetReadme(void* plugin) {
    (void)plugin;
    return "# SkillsFS (MVP)\n"
           "- write JSON or text to /execute to queue a run\n"
           "- read /result to trigger lazy execution (first read runs, later reads hit cache)\n"
           "- /status exposes JSON state, /log keeps an append-only log\n";
}

/*------------------------- FS Helpers -------------------------------*/
static FileInfoC *make_file_info(const char *name, int is_dir) {
    FileInfoC *info = (FileInfoC *)malloc(sizeof(FileInfoC));
    if (!info) return NULL;
    time_t now = time(NULL);
    info->Name = dup_string(name);
    info->Size = 0;
    info->Mode = is_dir ? 0755 : 0644;
    info->ModTime = now;
    info->IsDir = is_dir;
    info->MetaName = dup_string("skillsfs");
    info->MetaType = dup_string(is_dir ? "directory" : "file");
    info->MetaContent = dup_string("{}");
    return info;
}

static const char *file_names[] = {
    "metadata",
    "instructions",
    "execute",
    "result",
    "status",
    "log"
};

static int is_known_file(const char *name) {
    for (size_t i = 0; i < sizeof(file_names)/sizeof(file_names[0]); ++i) {
        if (strcmp(name, file_names[i]) == 0) return 1;
    }
    return 0;
}

/*------------------------- FS Operations ----------------------------*/
FileInfoC* FSStat(void* plugin, const char* path) {
    (void)plugin;
    if (strcmp(path, "/") == 0) return make_file_info("", 1);
    if (path[0] == '/' && is_known_file(path + 1)) {
        return make_file_info(path + 1, 0);
    }
    return NULL;
}

FileInfoArray* FSReadDir(void* plugin, const char* path, int* out_count) {
    (void)plugin;
    if (strcmp(path, "/") != 0) {
        *out_count = -1;
        return NULL;
    }
    FileInfoArray *arr = (FileInfoArray *)malloc(sizeof(FileInfoArray));
    if (!arr) {
        *out_count = -1;
        return NULL;
    }
    size_t count = sizeof(file_names)/sizeof(file_names[0]);
    arr->Items = (FileInfoC *)malloc(sizeof(FileInfoC) * count);
    if (!arr->Items) {
        free(arr);
        *out_count = -1;
        return NULL;
    }
    arr->Count = (int)count;
    time_t now = time(NULL);
    for (size_t i = 0; i < count; ++i) {
        arr->Items[i].Name = dup_string(file_names[i]);
        arr->Items[i].Size = 0;
        arr->Items[i].Mode = 0644;
        arr->Items[i].ModTime = now;
        arr->Items[i].IsDir = 0;
        arr->Items[i].MetaName = dup_string("skillsfs");
        arr->Items[i].MetaType = dup_string("file");
        arr->Items[i].MetaContent = dup_string("{}");
    }
    *out_count = arr->Count;
    return arr;
}

static const char *handle_execute_write(SkillFS *fs, const char *data, int data_len) {
    char *payload = (char *)malloc(data_len + 1);
    if (!payload) return "allocation failure";
    memcpy(payload, data, data_len);
    payload[data_len] = '\0';
    free_string(&fs->last_params);
    fs->last_params = payload;
    fs->pending = 1;
    fs->last_request_ts = time(NULL);
    set_status(fs, "pending", 0);
    append_log(fs, "INFO", "Received new execution payload");
    return NULL;
}

const char* FSWrite(void* plugin, const char* path, const char* data, int data_len) {
    SkillFS *fs = (SkillFS *)plugin;
    if (!fs) return "plugin is null";
    if (strcmp(path, "/execute") == 0) {
        return handle_execute_write(fs, data, data_len);
    }
    if (strcmp(path, "/instructions") == 0) {
        char *copy = (char *)malloc(data_len + 1);
        if (!copy) return "allocation failure";
        memcpy(copy, data, data_len);
        copy[data_len] = '\0';
        free_string(&fs->instructions);
        fs->instructions = copy;
        append_log(fs, "INFO", "Updated instructions");
        return NULL;
    }
    if (strcmp(path, "/metadata") == 0) {
        char *copy = (char *)malloc(data_len + 1);
        if (!copy) return "allocation failure";
        memcpy(copy, data, data_len);
        copy[data_len] = '\0';
        free_string(&fs->metadata);
        fs->metadata = copy;
        append_log(fs, "INFO", "Updated metadata");
        return NULL;
    }
    return "write not supported on this path";
}

const char* FSCreate(void* plugin, const char* path) { (void)plugin; (void)path; return "create not supported"; }
const char* FSMkdir(void* plugin, const char* path, uint32_t mode) { (void)plugin; (void)path; (void)mode; return "mkdir not supported"; }
const char* FSRemove(void* plugin, const char* path) { (void)plugin; (void)path; return "remove not supported"; }
const char* FSRemoveAll(void* plugin, const char* path) { (void)plugin; (void)path; return "removeall not supported"; }
const char* FSRename(void* plugin, const char* old_path, const char* new_path) { (void)plugin; (void)old_path; (void)new_path; return "rename not supported"; }
const char* FSChmod(void* plugin, const char* path, uint32_t mode) { (void)plugin; (void)path; (void)mode; return "chmod not supported"; }

static char *make_read_response(const char *src) {
    if (!src) src = "";
    return dup_string(src);
}

const char* FSRead(void* plugin, const char* path, int64_t offset, int64_t size, int* out_len) {
    SkillFS *fs = (SkillFS *)plugin;
    if (!fs) {
        *out_len = -1;
        return "plugin is null";
    }
    char *dynamic = NULL;
    if (strcmp(path, "/metadata") == 0) {
        dynamic = make_read_response(fs->metadata ? fs->metadata : "No metadata set\n");
    } else if (strcmp(path, "/instructions") == 0) {
        dynamic = make_read_response(fs->instructions ? fs->instructions : "No instructions set\n");
    } else if (strcmp(path, "/status") == 0) {
        dynamic = make_read_response(fs->status_json ? fs->status_json : "{}");
    } else if (strcmp(path, "/log") == 0) {
        dynamic = make_read_response((fs->log_text && fs->log_len > 0) ? fs->log_text : "No log entries yet\n");
    } else if (strcmp(path, "/result") == 0) {
        int cache_hit = 0;
        const char *err = ensure_result_current(fs, &cache_hit);
        if (err && !fs->last_result) {
            dynamic = make_read_response(err);
        } else if (fs->last_result) {
            dynamic = make_read_response(fs->last_result);
        } else {
            dynamic = make_read_response("No result available\n");
        }
        (void)cache_hit;
    } else {
        *out_len = -1;
        return "unsupported path";
    }

    if (!dynamic) {
        *out_len = -1;
        return "allocation failure";
    }
    size_t len = strlen(dynamic);
    if (offset >= (int64_t)len) {
        free(dynamic);
        *out_len = 0;
        return dup_string("");
    }
    int64_t remaining = len - offset;
    int64_t read_len = (size > 0 && size < remaining) ? size : remaining;
    char *slice = (char *)malloc(read_len + 1);
    if (!slice) {
        free(dynamic);
        *out_len = -1;
        return "allocation failure";
    }
    memcpy(slice, dynamic + offset, read_len);
    slice[read_len] = '\0';
    *out_len = read_len;
    free(dynamic);
    return slice;
}
