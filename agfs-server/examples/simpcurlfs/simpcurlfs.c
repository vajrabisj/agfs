#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <stdint.h>
#include <curl/curl.h>

#define SIMPCURLFS_VERSION "0.1.0"

#include "yyjson.h"

typedef struct {
    char *api_key;
    char *endpoint;
    int default_max_results;
    char *last_response;
    size_t last_response_len;
    char *pretty_summary;
    int initialized;
} SimpCurlFS;

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

static const char *ensure_api_key(SimpCurlFS *fs) {
    if (fs->api_key && strlen(fs->api_key) > 0) return NULL;
    const char *env_key = getenv("PERPLEXITY_API_KEY");
    if (env_key && *env_key) {
        fs->api_key = dup_string(env_key);
        return NULL;
    }
    return "PERPLEXITY_API_KEY is not set and no api_key provided";
}

static char *format_results(const char *json, size_t len, int max_results) {
    yyjson_doc *doc = yyjson_read(json, len, 0);
    if (!doc) {
        return dup_string("Failed to parse JSON response\n");
    }
    yyjson_val *root = yyjson_doc_get_root(doc);
    yyjson_val *results = yyjson_obj_get(root, "results");
    char *buffer = NULL;
    size_t cur_len = 0, cap = 0;
    if (!results || !yyjson_is_arr(results)) {
        append_text(&buffer, &cur_len, &cap, "No 'results' array in response\n");
        yyjson_doc_free(doc);
        return buffer;
    }
    append_text(&buffer, &cur_len, &cap, "Perplexity Search Results\n------------------------------\n");
    yyjson_arr_iter iter;
    yyjson_val *item;
    yyjson_arr_iter_init(results, &iter);
    int count = 0;
    while ((item = yyjson_arr_iter_next(&iter)) != NULL) {
        if (max_results > 0 && count >= max_results) break;
        yyjson_val *title_val = yyjson_obj_get(item, "title");
        yyjson_val *url_val = yyjson_obj_get(item, "url");
        yyjson_val *snippet_val = yyjson_obj_get(item, "snippet");
        const char *title = yyjson_get_str(title_val);
        const char *url = yyjson_get_str(url_val);
        const char *snippet = yyjson_get_str(snippet_val);
        char line[512];
        snprintf(line, sizeof(line), "Result %d\n", count + 1);
        append_text(&buffer, &cur_len, &cap, line);
        if (title) {
            append_text(&buffer, &cur_len, &cap, "  Title: ");
            append_text(&buffer, &cur_len, &cap, title);
            append_text(&buffer, &cur_len, &cap, "\n");
        }
        if (url) {
            append_text(&buffer, &cur_len, &cap, "  URL: ");
            append_text(&buffer, &cur_len, &cap, url);
            append_text(&buffer, &cur_len, &cap, "\n");
        }
        if (snippet) {
            append_text(&buffer, &cur_len, &cap, "  Snippet: ");
            append_text(&buffer, &cur_len, &cap, snippet);
            append_text(&buffer, &cur_len, &cap, "\n");
        }
        append_text(&buffer, &cur_len, &cap, "\n");
        count++;
    }
    if (count == 0) {
        append_text(&buffer, &cur_len, &cap, "No results returned\n");
    }
    yyjson_doc_free(doc);
    return buffer;
}

static const char *perform_search(SimpCurlFS *fs, const char *query, int max_results) {
    const char *key_err = ensure_api_key(fs);
    if (key_err) {
        return key_err;
    }
    CURL *curl = curl_easy_init();
    if (!curl) {
        return "curl_easy_init failed";
    }

    char payload[2048];
    if (max_results <= 0) {
        max_results = fs->default_max_results;
    }
    snprintf(payload, sizeof(payload), "{\"query\":\"%s\",\"max_results\":%d}", query, max_results);

    struct curl_slist *headers = NULL;
    headers = curl_slist_append(headers, "Content-Type: application/json");

    char auth_header[1024];
    snprintf(auth_header, sizeof(auth_header), "Authorization: Bearer %s", fs->api_key);
    headers = curl_slist_append(headers, auth_header);

    MemoryBuffer chunk = {0};
    chunk.data = malloc(1);
    chunk.size = 0;

    curl_easy_setopt(curl, CURLOPT_URL, fs->endpoint ? fs->endpoint : "https://api.perplexity.ai/search");
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, payload);
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, curl_write_cb);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, (void *)&chunk);

    CURLcode res = curl_easy_perform(curl);
    if (res != CURLE_OK) {
        curl_slist_free_all(headers);
        curl_easy_cleanup(curl);
        free(chunk.data);
        return curl_easy_strerror(res);
    }

    free_string(&fs->last_response);
    fs->last_response = chunk.data;
    fs->last_response_len = chunk.size;

    free_string(&fs->pretty_summary);
    fs->pretty_summary = format_results(chunk.data, chunk.size, max_results);

    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);
    return NULL;
}

void* PluginNew() {
    SimpCurlFS *fs = (SimpCurlFS *)calloc(1, sizeof(SimpCurlFS));
    if (!fs) return NULL;
    fs->default_max_results = 3;
    fs->endpoint = dup_string("https://api.perplexity.ai/search");
    return fs;
}

void PluginFree(void* plugin) {
    if (!plugin) return;
    SimpCurlFS *fs = (SimpCurlFS *)plugin;
    free_string(&fs->api_key);
    free_string(&fs->endpoint);
    free_string(&fs->last_response);
    free_string(&fs->pretty_summary);
    free(fs);
}

const char* PluginName(void* plugin) {
    (void)plugin;
    return "simpcurlfs";
}

static const char *apply_config(SimpCurlFS *fs, const char *config_json) {
    if (!config_json || strlen(config_json) == 0) {
        return NULL;
    }
    yyjson_doc *doc = yyjson_read(config_json, strlen(config_json), 0);
    if (!doc) return "invalid config json";
    yyjson_val *root = yyjson_doc_get_root(doc);
    yyjson_val *api_key_val = yyjson_obj_get(root, "api_key");
    yyjson_val *api_env_val = yyjson_obj_get(root, "api_key_env");
    yyjson_val *endpoint_val = yyjson_obj_get(root, "endpoint");
    yyjson_val *max_val = yyjson_obj_get(root, "default_max_results");

    if (api_key_val && yyjson_is_str(api_key_val)) {
        free_string(&fs->api_key);
        fs->api_key = dup_string(yyjson_get_str(api_key_val));
    } else if (api_env_val && yyjson_is_str(api_env_val)) {
        const char *env_name = yyjson_get_str(api_env_val);
        if (env_name && *env_name) {
            const char *env_val = getenv(env_name);
            if (env_val && *env_val) {
                free_string(&fs->api_key);
                fs->api_key = dup_string(env_val);
            }
        }
    }

    if (endpoint_val && yyjson_is_str(endpoint_val)) {
        free_string(&fs->endpoint);
        fs->endpoint = dup_string(yyjson_get_str(endpoint_val));
    }

    if (max_val && yyjson_is_int(max_val)) {
        fs->default_max_results = (int)yyjson_get_int(max_val);
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
    SimpCurlFS *fs = (SimpCurlFS *)plugin;
    if (!fs) return "plugin is null";
    const char *cfg_err = apply_config(fs, config_json);
    if (cfg_err) return cfg_err;
    fs->initialized = 1;
    return NULL;
}

const char* PluginShutdown(void* plugin) {
    SimpCurlFS *fs = (SimpCurlFS *)plugin;
    if (!fs) return "plugin is null";
    fs->initialized = 0;
    return NULL;
}

const char* PluginGetReadme(void* plugin) {
    (void)plugin;
    return "# SimpCurlFS\n"
           "Simple Perplexity search filesystem built in C.\n\n"
           "## Files\n"
           "- /request (write JSON: {\"query\":\"...\", \"max_results\":3})\n"
           "- /response.json (raw JSON from API)\n"
           "- /response.txt (formatted summary)\n\n"
           "Provide PERPLEXITY_API_KEY env or api_key config.\n";
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
    info->MetaName = dup_string("simpcurlfs");
    info->MetaType = dup_string(is_dir ? "directory" : "file");
    info->MetaContent = dup_string("{}");
    return info;
}

FileInfoC* FSStat(void* plugin, const char* path) {
    SimpCurlFS *fs = (SimpCurlFS *)plugin;
    if (!fs) return NULL;
    if (strcmp(path, "/") == 0) {
        return alloc_file_info("", 1, 0, 0755);
    }
    if (strcmp(path, "/request") == 0) {
        return alloc_file_info("request", 0, 0, 0644);
    }
    if (strcmp(path, "/response.json") == 0) {
        size_t sz = fs->last_response ? fs->last_response_len : 0;
        return alloc_file_info("response.json", 0, sz, 0644);
    }
    if (strcmp(path, "/response.txt") == 0) {
        size_t sz = fs->pretty_summary ? strlen(fs->pretty_summary) : 0;
        return alloc_file_info("response.txt", 0, sz, 0644);
    }
    return NULL;
}

FileInfoArray* FSReadDir(void* plugin, const char* path, int* out_count) {
    if (strcmp(path, "/") != 0) {
        *out_count = -1;
        return NULL;
    }
    FileInfoArray *array = (FileInfoArray *)malloc(sizeof(FileInfoArray));
    if (!array) {
        *out_count = -1;
        return NULL;
    }
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
        array->Items[i].MetaName = dup_string("simpcurlfs");
        array->Items[i].MetaType = dup_string("file");
        array->Items[i].MetaContent = dup_string("{}");
    }
    *out_count = array->Count;
    return array;
}

static const char *handle_request_write(SimpCurlFS *fs, const char *data, int data_len) {
    char *payload = (char *)malloc(data_len + 1);
    if (!payload) return "allocation failure";
    memcpy(payload, data, data_len);
    payload[data_len] = '\0';

    yyjson_doc *doc = yyjson_read(payload, data_len, 0);
    char *query = NULL;
    int max_results = fs->default_max_results;
    if (doc) {
        yyjson_val *root = yyjson_doc_get_root(doc);
        yyjson_val *query_val = yyjson_obj_get(root, "query");
        if (query_val && yyjson_is_str(query_val)) {
            query = dup_string(yyjson_get_str(query_val));
        }
        yyjson_val *max_val = yyjson_obj_get(root, "max_results");
        if (max_val && yyjson_is_int(max_val)) {
            max_results = (int)yyjson_get_int(max_val);
        }
        yyjson_doc_free(doc);
    } else {
        query = dup_string(payload);
    }

    free(payload);
    if (!query || strlen(query) == 0) {
        free_string(&query);
        return "request missing query";
    }

    const char *err = perform_search(fs, query, max_results);
    free_string(&query);
    return err;
}

const char* FSWrite(void* plugin, const char* path, const char* data, int data_len) {
    SimpCurlFS *fs = (SimpCurlFS *)plugin;
    if (!fs) return "plugin is null";
    if (strcmp(path, "/request") != 0) {
        return "write supported only on /request";
    }
    return handle_request_write(fs, data, data_len);
}

const char* FSCreate(void* plugin, const char* path) {
    (void)plugin; (void)path;
    return "create not supported";
}

const char* FSMkdir(void* plugin, const char* path, uint32_t mode) {
    (void)plugin; (void)path; (void)mode;
    return "mkdir not supported";
}

const char* FSRemove(void* plugin, const char* path) {
    (void)plugin; (void)path;
    return "remove not supported";
}

const char* FSRemoveAll(void* plugin, const char* path) {
    (void)plugin; (void)path;
    return "removeall not supported";
}

const char* FSRename(void* plugin, const char* old_path, const char* new_path) {
    (void)plugin; (void)old_path; (void)new_path;
    return "rename not supported";
}

const char* FSChmod(void* plugin, const char* path, uint32_t mode) {
    (void)plugin; (void)path; (void)mode;
    return "chmod not supported";
}

const char* FSRead(void* plugin, const char* path, int64_t offset, int64_t size, int* out_len) {
    SimpCurlFS *fs = (SimpCurlFS *)plugin;
    if (!fs) {
        *out_len = -1;
        return "plugin is null";
    }
    if (strcmp(path, "/response.json") == 0) {
        if (!fs->last_response) {
            const char *msg = "No response yet\n";
            *out_len = strlen(msg);
            char *copy = dup_string(msg);
            return copy;
        }
        if (offset >= (int64_t)fs->last_response_len) {
            *out_len = 0;
            return dup_string("");
        }
        int64_t remaining = fs->last_response_len - offset;
        int64_t read_len = (size > 0 && size < remaining) ? size : remaining;
        char *copy = (char *)malloc(read_len + 1);
        memcpy(copy, fs->last_response + offset, read_len);
        copy[read_len] = '\0';
        *out_len = read_len;
        return copy;
    }
    if (strcmp(path, "/response.txt") == 0) {
        const char *src = fs->pretty_summary ? fs->pretty_summary : "No response yet\n";
        size_t len = strlen(src);
        if (offset >= (int64_t)len) {
            *out_len = 0;
            return dup_string("");
        }
        int64_t remaining = len - offset;
        int64_t read_len = (size > 0 && size < remaining) ? size : remaining;
        char *copy = (char *)malloc(read_len + 1);
        memcpy(copy, src + offset, read_len);
        copy[read_len] = '\0';
        *out_len = read_len;
        return copy;
    }
    *out_len = -1;
    return "unsupported path";
}
