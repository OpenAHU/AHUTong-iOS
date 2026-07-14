#ifndef AHUTong_Bridging_Header_h
#define AHUTong_Bridging_Header_h

#include <stdint.h>

char *ahutong_start_server(uint16_t port);
void ahutong_stop_server(void);
void ahutong_free_string(char *value);
char *ahutong_init_persistence(
    const char *storage_path,
    const char *seed_cookies_json,
    uint8_t persist_session
);
char *ahutong_persist_current_cookies(void);
char *ahutong_kv_put_string(const char *box_name, const char *key, const char *value);
char *ahutong_kv_get_string(const char *box_name, const char *key);
char *ahutong_kv_remove(const char *box_name, const char *key);
char *ahutong_kv_clear_box(const char *box_name);

#endif
