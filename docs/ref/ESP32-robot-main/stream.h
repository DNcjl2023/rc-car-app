#ifndef STREAM_H
#define STREAM_H

#include "esp_camera.h"
#include "esp_http_server.h"

// Declare the function prototypes
//typedef int (*command_callback)(char[32]);

// Declare the variables as `extern`
extern const char *ssid;
extern const char *password;
extern httpd_handle_t camera_httpd;
extern httpd_handle_t stream_httpd;
extern int (*global_callback)(char*);



void startCameraServer(int (*callback)(char*));
void initCameraServer();

#endif