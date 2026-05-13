#include <cstdio>
#include <cstring>
#include <string>
#include <ctime>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/queue.h"
#include "esp_log.h"
#include "esp_system.h"
#include "esp_event.h"
#include "esp_wifi.h"
#include "esp_netif.h"
#include "esp_eth.h"
#include "esp_http_client.h"
#include "mqtt_client.h"
#include "cJSON.h"
#include "driver/gpio.h"
#include "driver/adc.h"
#include "esp_adc_cal.h"

// ============================================================
// CONFIGURATION
// ============================================================
static const char *TAG = "chute-firmware";
static const char *FIRMWARE_VERSION = "1.0.0";
static const char *ROOM_ID = "CHR_01";
static const char *MQTT_BROKER_URI = "mqtt://mosquitto:1883";
static const int TELEMETRY_INTERVAL_MS = 5000;
static const int MQTT_CONNECT_TIMEOUT_MS = 30000;

// ============================================================
// GPIO CONFIGURATION (Waveshare ESP32-S3 PoE)
// ============================================================
#define GPIO_DOOR_SENSOR 2      // Magnetic door contact sensor
#define GPIO_BLOCKAGE_SENSOR 3  // Ultrasonic/IR blockage sensor
#define GPIO_LEAK_SENSOR 4      // Water leak detection sensor
#define GPIO_MOTION_SENSOR 5    // Motion sensor
#define GPIO_BUZZER 6           // Alarm buzzer (relay)
#define GPIO_WARNING_LIGHT 7    // Warning light (relay)
#define GPIO_RESET_BUTTON 8     // Emergency reset button

// ============================================================
// SENSOR THRESHOLDS & CALIBRATION
// ============================================================
#define BLOCKAGE_THRESHOLD_CM 10      // Chute blocked if closer than 10cm
#define LEAK_ADC_THRESHOLD 2000       // Leak detected if ADC > 2000
#define DOOR_PROLONGED_OPEN_SEC 120   // Alert if door open for 2 minutes

// ============================================================
// GLOBAL STATE
// ============================================================
static esp_mqtt_client_handle_t mqtt_client = nullptr;
static uint32_t uptime_seconds = 0;
static uint32_t door_open_start_time = 0;
static uint32_t mqtt_reconnect_delay = 1000; // Start with 1 second backoff
static const uint32_t MAX_MQTT_RECONNECT_DELAY = 60000; // Max 60 seconds
static uint32_t mqtt_connect_attempts = 0;

// Current sensor state
struct SensorState {
    bool door_open;
    bool blockage_detected;
    bool leak_detected;
    bool motion_detected;
    uint16_t ultrasonic_distance_cm;
    uint16_t temperature;
    uint16_t humidity;
} sensor_state = {
    .door_open = false,
    .blockage_detected = false,
    .leak_detected = false,
    .motion_detected = false,
    .ultrasonic_distance_cm = 150,
    .temperature = 25,
    .humidity = 50
};

// ============================================================
// INITIALIZATION FUNCTIONS
// ============================================================

void init_gpio(void) {
    ESP_LOGI(TAG, "Initializing GPIO pins");
    
    // Configure input pins
    gpio_config_t input_config = {};
    input_config.pin_bit_mask = (1ULL << GPIO_DOOR_SENSOR) | 
                                (1ULL << GPIO_BLOCKAGE_SENSOR) | 
                                (1ULL << GPIO_LEAK_SENSOR) | 
                                (1ULL << GPIO_MOTION_SENSOR) |
                                (1ULL << GPIO_RESET_BUTTON);
    input_config.mode = GPIO_MODE_INPUT;
    input_config.pull_up_en = GPIO_PULLUP_ENABLE;
    input_config.pull_down_en = GPIO_PULLDOWN_DISABLE;
    input_config.intr_type = GPIO_INTR_DISABLE;
    gpio_config(&input_config);
    
    // Configure output pins (relays)
    gpio_config_t output_config = {};
    output_config.pin_bit_mask = (1ULL << GPIO_BUZZER) | 
                                 (1ULL << GPIO_WARNING_LIGHT);
    output_config.mode = GPIO_MODE_OUTPUT;
    output_config.pull_up_en = GPIO_PULLUP_DISABLE;
    output_config.pull_down_en = GPIO_PULLDOWN_DISABLE;
    output_config.intr_type = GPIO_INTR_DISABLE;
    gpio_config(&output_config);
    
    // Initialize relays to OFF
    gpio_set_level(GPIO_BUZZER, 0);
    gpio_set_level(GPIO_WARNING_LIGHT, 0);
}

void init_adc(void) {
    ESP_LOGI(TAG, "Initializing ADC for sensor readings");
    adc1_config_width(ADC_WIDTH_BIT_12);
    adc1_config_channel_atten(ADC1_CHANNEL_5, ADC_ATTEN_DB_12);
}

// ============================================================
// SENSOR READING FUNCTIONS
// ============================================================

void read_sensors(void) {
    // Read door sensor (magnetic contact)
    bool new_door_state = gpio_get_level(GPIO_DOOR_SENSOR) == 0;
    if (new_door_state != sensor_state.door_open) {
        sensor_state.door_open = new_door_state;
        if (new_door_state) {
            door_open_start_time = uptime_seconds;
            ESP_LOGI(TAG, "Door opened");
        } else {
            ESP_LOGI(TAG, "Door closed after %lu seconds", uptime_seconds - door_open_start_time);
            door_open_start_time = 0;
        }
    }
    
    // Read blockage sensor (ultrasonic)
    // TODO: Implement actual ultrasonic distance measurement
    // For now, simulating with random values in demo mode
    sensor_state.ultrasonic_distance_cm = 50 + (esp_random() % 100);
    sensor_state.blockage_detected = sensor_state.ultrasonic_distance_cm < BLOCKAGE_THRESHOLD_CM;
    
    // Read leak sensor (ADC from water detection)
    uint16_t leak_adc = adc1_get_raw(ADC1_CHANNEL_5);
    sensor_state.leak_detected = leak_adc > LEAK_ADC_THRESHOLD;
    
    // Read motion sensor
    sensor_state.motion_detected = gpio_get_level(GPIO_MOTION_SENSOR) == 1;
}

// ============================================================
// RELAY CONTROL FUNCTIONS
// ============================================================

void trigger_buzzer(uint32_t duration_ms) {
    ESP_LOGI(TAG, "Buzzer triggered for %lu ms", duration_ms);
    gpio_set_level(GPIO_BUZZER, 1);
    vTaskDelay(pdMS_TO_TICKS(duration_ms));
    gpio_set_level(GPIO_BUZZER, 0);
}

void trigger_warning_light(bool on) {
    ESP_LOGI(TAG, "Warning light %s", on ? "ON" : "OFF");
    gpio_set_level(GPIO_WARNING_LIGHT, on ? 1 : 0);
}

// ============================================================
// TELEMETRY PUBLISHING
// ============================================================

void publish_telemetry(void) {
    if (!mqtt_client) {
        ESP_LOGW(TAG, "MQTT client not initialized");
        return;
    }
    
    read_sensors();
    
    cJSON *root = cJSON_CreateObject();
    cJSON_AddStringToObject(root, "room_id", ROOM_ID);
    cJSON_AddBoolToObject(root, "door_open", sensor_state.door_open);
    cJSON_AddBoolToObject(root, "blockage", sensor_state.blockage_detected);
    cJSON_AddBoolToObject(root, "leak_detected", sensor_state.leak_detected);
    cJSON_AddBoolToObject(root, "motion_detected", sensor_state.motion_detected);
    cJSON_AddNumberToObject(root, "ultrasonic_distance_cm", sensor_state.ultrasonic_distance_cm);
    cJSON_AddNumberToObject(root, "temperature", sensor_state.temperature);
    cJSON_AddNumberToObject(root, "humidity", sensor_state.humidity);
    cJSON_AddNumberToObject(root, "uptime_sec", uptime_seconds);
    cJSON_AddNumberToObject(root, "timestamp", (double)time(nullptr));
    
    char *json = cJSON_PrintUnformatted(root);
    if (json) {
        char topic[128];
        snprintf(topic, sizeof(topic), "garbage/telemetry/%s", ROOM_ID);
        int msg_id = esp_mqtt_client_publish(mqtt_client, topic, json, 0, 1, 0);
        ESP_LOGI(TAG, "Telemetry published (msg_id=%d)", msg_id);
        cJSON_free(json);
    }
    cJSON_Delete(root);
    
    // Trigger alerts if needed
    if (sensor_state.blockage_detected) {
        trigger_warning_light(true);
        trigger_buzzer(500);
    } else {
        trigger_warning_light(false);
    }
    
    // Check for prolonged open door
    if (sensor_state.door_open) {
        uint32_t door_open_duration = uptime_seconds - door_open_start_time;
        if (door_open_duration > DOOR_PROLONGED_OPEN_SEC) {
            trigger_buzzer(200);
        }
    }
}

void publish_device_info(void) {
    if (!mqtt_client) {
        ESP_LOGW(TAG, "MQTT client not initialized");
        return;
    }
    
    cJSON *root = cJSON_CreateObject();
    cJSON_AddStringToObject(root, "room_id", ROOM_ID);
    cJSON_AddStringToObject(root, "device_id", "ESP32-CHR-01");
    cJSON_AddStringToObject(root, "firmware_version", FIRMWARE_VERSION);
    cJSON_AddNumberToObject(root, "uptime_sec", uptime_seconds);
    cJSON_AddNumberToObject(root, "rssi", 0); // Signal strength TODO
    cJSON_AddNumberToObject(root, "free_heap", esp_get_free_heap_size());
    cJSON_AddNumberToObject(root, "timestamp", (double)time(nullptr));
    
    char *json = cJSON_PrintUnformatted(root);
    if (json) {
        char topic[128];
        snprintf(topic, sizeof(topic), "garbage/device/%s/status", ROOM_ID);
        esp_mqtt_client_publish(mqtt_client, topic, json, 0, 1, 0);
        cJSON_free(json);
    }
    cJSON_Delete(root);
}

// ============================================================
// MQTT EVENT HANDLER
// ============================================================

static void mqtt_event_handler(void *handler_args, esp_event_base_t base, int32_t event_id, void *event_data) {
    esp_mqtt_event_handle_t event = (esp_mqtt_event_handle_t) event_data;
    
    switch (event->event_id) {
    case MQTT_EVENT_CONNECTED:
        ESP_LOGI(TAG, "MQTT_EVENT_CONNECTED");
        mqtt_reconnect_delay = 1000;
        mqtt_connect_attempts = 0;
        
        // Subscribe to command topics
        char cmd_topic[128];
        snprintf(cmd_topic, sizeof(cmd_topic), "garbage/room/%s/cmd/#", ROOM_ID);
        esp_mqtt_client_subscribe(mqtt_client, cmd_topic, 1);
        
        // Publish device info
        publish_device_info();
        break;
        
    case MQTT_EVENT_DISCONNECTED:
        ESP_LOGW(TAG, "MQTT_EVENT_DISCONNECTED");
        break;
        
    case MQTT_EVENT_SUBSCRIBED:
        ESP_LOGI(TAG, "MQTT_EVENT_SUBSCRIBED, msg_id=%d", event->msg_id);
        break;
        
    case MQTT_EVENT_UNSUBSCRIBED:
        ESP_LOGI(TAG, "MQTT_EVENT_UNSUBSCRIBED, msg_id=%d", event->msg_id);
        break;
        
    case MQTT_EVENT_PUBLISHED:
        ESP_LOGD(TAG, "MQTT_EVENT_PUBLISHED, msg_id=%d", event->msg_id);
        break;
        
    case MQTT_EVENT_DATA:
        ESP_LOGI(TAG, "MQTT_EVENT_DATA");
        ESP_LOGI(TAG, "TOPIC=%.*s", event->topic_len, event->topic);
        ESP_LOGI(TAG, "DATA=%.*s", event->data_len, event->data);
        
        // Parse and handle commands
        cJSON *root = cJSON_ParseWithLength(event->data, event->data_len);
        if (root) {
            cJSON *cmd = cJSON_GetObjectItem(root, "command");
            if (cmd && cmd->valuestring) {
                if (strcmp(cmd->valuestring, "buzzer_on") == 0) {
                    trigger_buzzer(1000);
                } else if (strcmp(cmd->valuestring, "light_on") == 0) {
                    trigger_warning_light(true);
                } else if (strcmp(cmd->valuestring, "light_off") == 0) {
                    trigger_warning_light(false);
                } else if (strcmp(cmd->valuestring, "reset") == 0) {
                    ESP_LOGI(TAG, "Reset command received");
                    esp_restart();
                }
            }
            cJSON_Delete(root);
        }
        break;
        
    case MQTT_EVENT_ERROR:
        ESP_LOGE(TAG, "MQTT_EVENT_ERROR");
        break;
        
    default:
        ESP_LOGD(TAG, "Other mqtt event id:%d", event->event_id);
        break;
    }
}

// ============================================================
// MQTT INITIALIZATION WITH RECONNECT LOGIC
// ============================================================

void mqtt_init(void) {
    esp_mqtt_client_config_t mqtt_cfg = {};
    mqtt_cfg.broker.address.uri = MQTT_BROKER_URI;
    mqtt_cfg.credentials.username = "";
    mqtt_cfg.credentials.auth_type = MQTT_AUTH_TYPE_NONE;
    mqtt_cfg.network.timeout_ms = MQTT_CONNECT_TIMEOUT_MS;
    
    mqtt_client = esp_mqtt_client_init(&mqtt_cfg);
    if (!mqtt_client) {
        ESP_LOGE(TAG, "Failed to initialize MQTT client");
        return;
    }
    
    esp_mqtt_client_register_event(mqtt_client, MQTT_EVENT_ANY, mqtt_event_handler, nullptr);
    esp_mqtt_client_start(mqtt_client);
    ESP_LOGI(TAG, "MQTT client started");
}

// ============================================================
// UPTIME TASK
// ============================================================

void uptime_task(void *pvParameters) {
    while (true) {
        uptime_seconds++;
        vTaskDelay(pdMS_TO_TICKS(1000));
    }
}

// ============================================================
// TELEMETRY TASK
// ============================================================

void telemetry_task(void *pvParameters) {
    vTaskDelay(pdMS_TO_TICKS(2000)); // Wait for MQTT to connect
    
    while (true) {
        if (mqtt_client) {
            publish_telemetry();
        }
        vTaskDelay(pdMS_TO_TICKS(TELEMETRY_INTERVAL_MS));
    }
}

// ============================================================
// DEVICE INFO TASK (Publish every 60 seconds)
// ============================================================

void device_info_task(void *pvParameters) {
    while (true) {
        vTaskDelay(pdMS_TO_TICKS(60000));
        if (mqtt_client) {
            publish_device_info();
        }
    }
}

// ============================================================
// MAIN APPLICATION ENTRY POINT
// ============================================================

extern "C" void app_main(void) {
    esp_log_level_set(TAG, ESP_LOG_INFO);
    ESP_LOGI(TAG, "========================================");
    ESP_LOGI(TAG, "Smart Garbage Chute - ESP32-S3 Node");
    ESP_LOGI(TAG, "Room ID: %s", ROOM_ID);
    ESP_LOGI(TAG, "Firmware: %s", FIRMWARE_VERSION);
    ESP_LOGI(TAG, "========================================");
    
    // Initialize peripherals
    init_gpio();
    init_adc();
    
    // Initialize MQTT
    mqtt_init();
    
    // Create background tasks
    xTaskCreatePinnedToCore(uptime_task, "uptime_task", 2048, nullptr, 1, nullptr, 0);
    xTaskCreatePinnedToCore(telemetry_task, "telemetry_task", 4096, nullptr, 1, nullptr, 1);
    xTaskCreatePinnedToCore(device_info_task, "device_info_task", 2048, nullptr, 1, nullptr, 0);
    
    ESP_LOGI(TAG, "Device started successfully");
}
