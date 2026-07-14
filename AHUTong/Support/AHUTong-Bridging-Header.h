#ifndef AHUTong_Bridging_Header_h
#define AHUTong_Bridging_Header_h

#include <stdint.h>

char *ahutong_start_server(uint16_t port);
void ahutong_stop_server(void);
void ahutong_free_string(char *value);

#endif
