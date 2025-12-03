#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <stdint.h>
#include <curl/curl.h>

#define SUMMARYFS_VERSION "0.2.0"

#include "yyjson.h"

/*------------------------- Helper Structures -------------------------*/
typedef struct {
    char *model;
    char *endpoint;
    int timeout_ms;
    double temperature;
    char *system_prompt;
    char *api_key;
    char *api_key_env;
    char *last_raw;
    size_t last_raw_len;
    char *last_summary;
    int initialized;
} SummaryFS;

typedef struct {
    char *data;
    size_t size;
} MemoryBuffer;

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

/*------------------------- Utility Helpers ---------------------------*/
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

static size_t curl_write_cb(void *contents, size_t size, size_t nmemb, void *userp) {
    size_t realsize = size * nmemb;
    MemoryBuffer *mem = (MemoryBuffer *)userp;
    char *ptr = realloc(mem->data, mem->size + realsize + 1);
    if (!ptr) return 0;
    mem->data = ptr;
    memcpy(&(mem->data[mem->size]), contents, realsize);
    mem->size += realsize;
    mem->data[mem->size] = '\0';
    return realsize;
}

static FileInfoC *alloc_file_info(const char *name, int is_dir, int64_t size, uint32_t mode) {
    FileInfoC *info = (FileInfoC *)malloc(sizeof(FileInfoC));
    if (!info) return NULL;
    time_t now = time(NULL);
    info->Name = dup_string(name);
    info->Size = size;
    info->Mode = mode;
    info->ModTime = now;
    info->IsDir = is_dir;
    info->MetaName = dup_string("summaryfs");
    info->MetaType = dup_string(is_dir ? "directory" : "file");
    info->MetaContent = dup_string("{}");
    return info;
}

/*------------------------- OpenAI Invocation ------------------------*/
static const char *ensure_model(SummaryFS *fs) {
    if (!fs->model) {
        fs->model = dup_string("gpt-4o-mini");
    }
    if (!fs->model) return "failed to set default model";
    return NULL;
}

static const char *ensure_endpoint(SummaryFS *fs) {
    if (!fs->endpoint) {
        fs->endpoint = dup_string("https://api.openai.com/v1/chat/completions");
    }
    if (!fs->endpoint) return "failed to set default endpoint";
    return NULL;
}

static const char *ensure_api_key(SummaryFS *fs) {
    if (fs->api_key && fs->api_key[0]) return NULL;
    const char *candidate = NULL;
    if (fs->api_key_env && fs->api_key_env[0]) {
        candidate = getenv(fs->api_key_env);
    }
    if (!candidate || !candidate[0]) {
        candidate = getenv("OPENAI_API_KEY");
    }
    if (!candidate || !candidate[0]) {
        return "OpenAI API key not set (set OPENAI_API_KEY or openai_api_key(_env))";
    }
    free_string(&fs->api_key);
    fs->api_key = dup_string(candidate);
    if (!fs->api_key) return "failed to copy API key";
    return NULL;
}

static char *build_prompt(SummaryFS *fs, const char *text, const char *format) {
    const char *default_prompt =
        "You are a helpful research assistant. Summarize the provided text in a clear,\n"
        "concise way. Highlight key insights. If format is specified, follow it.";
    const char *sys = fs->system_prompt ? fs->system_prompt : default_prompt;

    size_t cap = strlen(sys) + strlen(text) + 256;
    char *prompt = (char *)malloc(cap);
    if (!prompt) return NULL;
    if (format && *format) {
        snprintf(prompt, cap, "%s\n\nFormat: %s\n\nText:\n%s", sys, format, text);
    } else {
        snprintf(prompt, cap, "%s\n\nText:\n%s", sys, text);
    }
    return prompt;
}

static const char *call_openai(SummaryFS *fs, const char *prompt) {
    const char *err;
    if ((err = ensure_model(fs)) != NULL) return err;
    if ((err = ensure_endpoint(fs)) != NULL) return err;
    if ((err = ensure_api_key(fs)) != NULL) return err;

    CURL *curl = curl_easy_init();
    if (!curl) return "curl_easy_init failed";

    yyjson_mut_doc *doc = yyjson_mut_doc_new(NULL);
    yyjson_mut_val *root = yyjson_mut_obj(doc);
    yyjson_mut_doc_set_root(doc, root);
    yyjson_mut_obj_add_str(doc, root, "model", fs->model);
    if (fs->temperature > 0.0) {
        yyjson_mut_obj_add_real(doc, root, "temperature", fs->temperature);
    }
    yyjson_mut_val *messages = yyjson_mut_arr(doc);
    yyjson_mut_obj_add_val(doc, root, "messages", messages);

    const char *sys = fs->system_prompt ? fs->system_prompt :
        "You are a helpful research assistant. Summarize the user text in a concise manner.";
    yyjson_mut_val *sys_msg = yyjson_mut_obj(doc);
    yyjson_mut_arr_add_val(messages, sys_msg);
    yyjson_mut_obj_add_str(doc, sys_msg, "role", "system");
    yyjson_mut_obj_add_str(doc, sys_msg, "content", sys);

    yyjson_mut_val *user_msg = yyjson_mut_obj(doc);
    yyjson_mut_arr_add_val(messages, user_msg);
    yyjson_mut_obj_add_str(doc, user_msg, "role", "user");
    yyjson_mut_obj_add_str(doc, user_msg, "content", prompt);

    size_t payload_len;
    char *payload = yyjson_mut_write(doc, 0, &payload_len);
    yyjson_mut_doc_free(doc);
    if (!payload) {
        curl_easy_cleanup(curl);
        return "failed to build request payload";
    }

    struct curl_slist *headers = NULL;
    headers = curl_slist_append(headers, "Content-Type: application/json");
    char auth_header[512];
    snprintf(auth_header, sizeof(auth_header), "Authorization: Bearer %s", fs->api_key);
    headers = curl_slist_append(headers, auth_header);

    MemoryBuffer chunk = {0};
    chunk.data = malloc(1);
    chunk.size = 0;

    curl_easy_setopt(curl, CURLOPT_URL, fs->endpoint);
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, payload);
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, curl_write_cb);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, (void *)&chunk);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT_MS, fs->timeout_ms > 0 ? fs->timeout_ms : 120000);

    CURLcode res = curl_easy_perform(curl);
    free(payload);
    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);

    if (res != CURLE_OK) {
        free(chunk.data);
        return curl_easy_strerror(res);
    }

    free_string(&fs->last_raw);
    fs->last_raw = chunk.data;
    fs->last_raw_len = chunk.size;
    return NULL;
}

static const char *extract_summary(SummaryFS *fs) {
    if (!fs->last_raw) return "no raw response";
    yyjson_doc *doc = yyjson_read(fs->last_raw, fs->last_raw_len, 0);
    if (!doc) {
        return "failed to parse LLM response";
    }
    yyjson_val *root = yyjson_doc_get_root(doc);
    yyjson_val *choices = yyjson_obj_get(root, "choices");
    const char *summary = NULL;
    if (choices && yyjson_is_arr(choices) && yyjson_arr_size(choices) > 0) {
        yyjson_val *first = yyjson_arr_get(choices, 0);
        if (first) {
            yyjson_val *message = yyjson_obj_get(first, "message");
            if (message) {
                yyjson_val *content = yyjson_obj_get(message, "content");
                if (content && yyjson_is_str(content)) {
                    summary = yyjson_get_str(content);
                }
            }
        }
    }
    if (!summary) summary = "(no content field returned)";
    free_string(&fs->last_summary);
    fs->last_summary = dup_string(summary);
    yyjson_doc_free(doc);
    if (!fs->last_summary) return "failed to copy summary";
    return NULL;
}

/*------------------------- Plugin Lifecycle -------------------------*/
void* PluginNew() {
    SummaryFS *fs = (SummaryFS *)calloc(1, sizeof(SummaryFS));
    if (!fs) return NULL;
    fs->timeout_ms = 120000;
    fs->temperature = 0.2;
    return fs;
}

void PluginFree(void* plugin) {
    if (!plugin) return;
    SummaryFS *fs = (SummaryFS *)plugin;
    free_string(&fs->model);
    free_string(&fs->endpoint);
    free_string(&fs->system_prompt);
    free_string(&fs->api_key);
    free_string(&fs->api_key_env);
    free_string(&fs->last_raw);
    free_string(&fs->last_summary);
    free(fs);
}

const char* PluginName(void* plugin) {
    (void)plugin;
    return "summaryfs";
}

static const char *apply_config(SummaryFS *fs, const char *config_json) {
    if (!config_json || strlen(config_json) == 0) return NULL;
    yyjson_doc *doc = yyjson_read(config_json, strlen(config_json), 0);
    if (!doc) return "invalid config json";
    yyjson_val *root = yyjson_doc_get_root(doc);
    yyjson_val *model_val = yyjson_obj_get(root, "model");
    if (!model_val) model_val = yyjson_obj_get(root, "openai_model");
    yyjson_val *endpoint_val = yyjson_obj_get(root, "openai_endpoint");
    yyjson_val *timeout_val = yyjson_obj_get(root, "timeout_ms");
    yyjson_val *temp_val = yyjson_obj_get(root, "temperature");
    yyjson_val *sys_val = yyjson_obj_get(root, "system_prompt");
    yyjson_val *key_val = yyjson_obj_get(root, "openai_api_key");
    yyjson_val *key_env_val = yyjson_obj_get(root, "openai_api_key_env");

    if (model_val && yyjson_is_str(model_val)) {
        free_string(&fs->model);
        fs->model = dup_string(yyjson_get_str(model_val));
    }
    if (endpoint_val && yyjson_is_str(endpoint_val)) {
        free_string(&fs->endpoint);
        fs->endpoint = dup_string(yyjson_get_str(endpoint_val));
    }
    if (timeout_val && yyjson_is_int(timeout_val)) {
        fs->timeout_ms = (int)yyjson_get_int(timeout_val);
    }
    if (temp_val && (yyjson_is_real(temp_val) || yyjson_is_int(temp_val))) {
        fs->temperature = yyjson_is_real(temp_val) ? yyjson_get_real(temp_val)
                                                   : (double)yyjson_get_int(temp_val);
    }
    if (sys_val && yyjson_is_str(sys_val)) {
        free_string(&fs->system_prompt);
        fs->system_prompt = dup_string(yyjson_get_str(sys_val));
    }
    if (key_val && yyjson_is_str(key_val)) {
        free_string(&fs->api_key);
        fs->api_key = dup_string(yyjson_get_str(key_val));
    }
    if (key_env_val && yyjson_is_str(key_env_val)) {
        free_string(&fs->api_key_env);
        fs->api_key_env = dup_string(yyjson_get_str(key_env_val));
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
    SummaryFS *fs = (SummaryFS *)plugin;
    if (!fs) return "plugin is null";
    const char *err = apply_config(fs, config_json);
    if (err) return err;
    fs->initialized = 1;
    return NULL;
}

const char* PluginShutdown(void* plugin) {
    SummaryFS *fs = (SummaryFS *)plugin;
    if (!fs) return "plugin is null";
    fs->initialized = 0;
    return NULL;
}

const char* PluginGetReadme(void* plugin) {
    (void)plugin;
    return "# SummaryFS\n"
           "Summarize arbitrary text via OpenAI Chat Completions (default model gpt-4o-mini).\n\n"
           "## Files\n"
           "- /request (write JSON or plain text)\n"
           "- /response.json (raw response)\n"
           "- /response.txt (summary)\n\n"
           "Config: openai_model, openai_endpoint, openai_api_key(_env), timeout_ms, temperature, system_prompt.\n";
}

/*------------------------- FS Operations ----------------------------*/
FileInfoC* FSStat(void* plugin, const char* path) {
    if (strcmp(path, "/") == 0) return alloc_file_info("", 1, 0, 0755);
    if (strcmp(path, "/request") == 0) return alloc_file_info("request", 0, 0, 0644);
    if (strcmp(path, "/response.json") == 0) return alloc_file_info("response.json", 0, 0, 0644);
    if (strcmp(path, "/response.txt") == 0) return alloc_file_info("response.txt", 0, 0, 0644);
    return NULL;
}

FileInfoArray* FSReadDir(void* plugin, const char* path, int* out_count) {
    if (strcmp(path, "/") != 0) {
        *out_count = -1;
        return NULL;
    }
    FileInfoArray *array = (FileInfoArray *)malloc(sizeof(FileInfoArray));
    array->Count = 3;
    array->Items = (FileInfoC *)malloc(sizeof(FileInfoC) * array->Count);
    time_t now = time(NULL);
    const char *names[] = {"request", "response.json", "response.txt"};
    for (int i = 0; i < array->Count; ++i) {
        array->Items[i].Name = dup_string(names[i]);
        array->Items[i].Size = 0;
        array->Items[i].Mode = 0644;
        array->Items[i].ModTime = now;
        array->Items[i].IsDir = 0;
        array->Items[i].MetaName = dup_string("summaryfs");
        array->Items[i].MetaType = dup_string("file");
        array->Items[i].MetaContent = dup_string("{}");
    }
    *out_count = array->Count;
    return array;
}

static const char *handle_request(SummaryFS *fs, const char *data, int len) {
    char *input = (char *)malloc(len + 1);
    if (!input) return "allocation failure";
    memcpy(input, data, len);
    input[len] = '\0';

    yyjson_doc *doc = yyjson_read(input, len, 0);
    char *text = NULL;
    char *format = NULL;
    if (doc) {
        yyjson_val *root = yyjson_doc_get_root(doc);
        yyjson_val *text_val = yyjson_obj_get(root, "text");
        if (text_val && yyjson_is_str(text_val)) {
            text = dup_string(yyjson_get_str(text_val));
        }
        yyjson_val *format_val = yyjson_obj_get(root, "format");
        if (format_val && yyjson_is_str(format_val)) {
            format = dup_string(yyjson_get_str(format_val));
        }
        yyjson_doc_free(doc);
    }

    if (!text || strlen(text) == 0) {
        free_string(&text);
        text = dup_string(input);
    }

    free(input);

    if (!text || strlen(text) == 0) {
        free_string(&text);
        free_string(&format);
        return "request missing text";
    }

    char *prompt = build_prompt(fs, text, format);
    free_string(&text);
    free_string(&format);
    if (!prompt) return "failed to build prompt";

    const char *err = call_openai(fs, prompt);
    free(prompt);
    if (err) return err;

    err = extract_summary(fs);
    return err;
}

const char* FSWrite(void* plugin, const char* path, const char* data, int data_len) {
    if (strcmp(path, "/request") != 0) {
        return "write supported only on /request";
    }
    SummaryFS *fs = (SummaryFS *)plugin;
    if (!fs) return "plugin is null";
    return handle_request(fs, data, data_len);
}

const char* FSCreate(void* plugin, const char* path) { (void)plugin; (void)path; return "create not supported"; }
const char* FSMkdir(void* plugin, const char* path, uint32_t mode) { (void)plugin; (void)path; (void)mode; return "mkdir not supported"; }
const char* FSRemove(void* plugin, const char* path) { (void)plugin; (void)path; return "remove not supported"; }
const char* FSRemoveAll(void* plugin, const char* path) { (void)plugin; (void)path; return "removeall not supported"; }
const char* FSRename(void* plugin, const char* old_path, const char* new_path) { (void)plugin; (void)old_path; (void)new_path; return "rename not supported"; }
const char* FSChmod(void* plugin, const char* path, uint32_t mode) { (void)plugin; (void)path; (void)mode; return "chmod not supported"; }

const char* FSRead(void* plugin, const char* path, int64_t offset, int64_t size, int* out_len) {
    SummaryFS *fs = (SummaryFS *)plugin;
    if (!fs) {
        *out_len = -1;
        return "plugin is null";
    }
    const char *src = NULL;
    size_t len = 0;
    if (strcmp(path, "/response.json") == 0) {
        src = fs->last_raw ? fs->last_raw : "No response yet\n";
        len = fs->last_raw ? fs->last_raw_len : strlen(src);
    } else if (strcmp(path, "/response.txt") == 0) {
        src = fs->last_summary ? fs->last_summary : "No summary yet\n";
        len = strlen(src);
    } else {
        *out_len = -1;
        return "unsupported path";
    }
    if (offset >= (int64_t)len) {
        *out_len = 0;
        return dup_string("");
    }
    int64_t remaining = len - offset;
    int64_t read_len = (size > 0 && size < remaining) ? size : remaining;
    char *copy = (char *)malloc(read_len + 1);
    if (!copy) {
        *out_len = -1;
        return "allocation failure";
    }
    memcpy(copy, src + offset, read_len);
    copy[read_len] = '\0';
    *out_len = read_len;
    return copy;
}
