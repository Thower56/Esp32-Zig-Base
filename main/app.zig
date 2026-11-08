const std = @import("std");
const idf = @import("esp_idf");
const sys = idf.sys;

const max_wifi_retries: u32 = 5;
const wifi_connected_bit: u32 = sys.WIFI_CONNECTED_BIT;
const wifi_failed_bit: u32 = sys.WIFI_FAIL_BIT;

var wifi_event_group: sys.EventGroupHandle_t = null;
var wifi_retry_count: u32 = 0;
var wifi_ip_addr: u32 = 0;
var wifi_callback_error: ?anyerror = null;

export fn app_main() callconv(.c) void {
    const result: u32 = 2 + 3;
    log.info("2 + 3 = {d}", .{result});

    connectWifi() catch |err| {
        log.err("Wi-Fi setup failed: {s}", .{@errorName(err)});
        return;
    };

    var config = idf.sys.camera_config_t{
        .pin_pwdn = 32,
        .pin_reset = -1,
        .pin_xclk = 0,
        // translate-c exposes the C SCCB pin unions as unnamed fields.
        .unnamed_0 = 26, // SDA
        .unnamed_1 = 27, // SCL
        .pin_d7 = 35,
        .pin_d6 = 34,
        .pin_d5 = 39,
        .pin_d4 = 36,
        .pin_d3 = 21,
        .pin_d2 = 19,
        .pin_d1 = 18,
        .pin_d0 = 5,
        .pin_vsync = 25,
        .pin_href = 23,
        .pin_pclk = 22,
        .xclk_freq_hz = 20_000_000,
        .ledc_timer = @intCast(idf.sys.LEDC_TIMER_0),
        .ledc_channel = @intCast(idf.sys.LEDC_CHANNEL_0),
        .pixel_format = @intCast(idf.sys.PIXFORMAT_JPEG),
        .frame_size = @intCast(idf.sys.FRAMESIZE_QVGA),
        .jpeg_quality = 12,
        .fb_count = 1,
        .fb_location = @intCast(idf.sys.CAMERA_FB_IN_PSRAM),
        .grab_mode = @intCast(idf.sys.CAMERA_GRAB_WHEN_EMPTY),
        .sccb_i2c_port = 0,
    };

    const init_result = idf.sys.esp_camera_init(&config);
    if (init_result != idf.sys.ESP_OK) {
        log.err("Camera initialization failed: {d}", .{init_result});
        return;
    }

    const frame = idf.sys.esp_camera_fb_get();
    if (frame == null) {
        log.err("Camera did not return a frame", .{});
        return;
    }
    defer idf.sys.esp_camera_fb_return(frame);

    log.info("Captured {d}x{d} JPEG frame ({d} bytes)", .{
        frame.*.width,
        frame.*.height,
        frame.*.len,
    });
}

fn connectWifi() !void {
    wifi_retry_count = 0;
    wifi_ip_addr = 0;
    wifi_callback_error = null;

    try idf.nvs.flashInitOrErase();

    wifi_event_group = sys.xEventGroupCreate() orelse return error.WifiEventGroupCreateFailed;
    try idf.err.espCheckError(sys.esp_netif_init());
    try idf.event.loopCreateDefault();
    if (sys.esp_netif_create_default_wifi_sta() == null) return error.WifiNetifCreateFailed;

    var wifi_init_config = idf.wifi.init_config_default();
    try idf.wifi.init(&wifi_init_config);

    _ = try idf.event.handlerInstanceRegister(sys.WIFI_EVENT, idf.event.ANY_ID, &onWifiEvent, null);
    _ = try idf.event.handlerInstanceRegister(sys.IP_EVENT, sys.IP_EVENT_STA_GOT_IP, &onIpEvent, null);

    var wifi_config = idf.wifi.wifiConfig{
        .sta = .{
            .ssid = std.mem.zeroes([32]u8),
            .password = std.mem.zeroes([64]u8),
            .threshold = .{
                .rssi = 0,
                .rssi_5g_adjustment = 0,
                .authmode = sys.WIFI_AUTH_WPA2_PSK,
            },
            .sae_pwe_h2e = sys.WPA3_SAE_PWE_BOTH,
            .sae_h2e_identifier = std.mem.zeroes([32]u8),
        },
    };
    copyZ(&wifi_config.sta.ssid, sys.CONFIG_ESP_WIFI_SSID);
    copyZ(&wifi_config.sta.password, sys.CONFIG_ESP_WIFI_PASSWORD);

    try idf.wifi.setMode(.WIFI_MODE_STA);
    try idf.wifi.setConfig(.WIFI_IF_STA, &wifi_config);
    try idf.wifi.start();

    log.info("Connecting to Wi-Fi...", .{});
    const bits = sys.xEventGroupWaitBits(
        wifi_event_group,
        wifi_connected_bit | wifi_failed_bit,
        0,
        0,
        sys.portMAX_DELAY,
    );
    if ((bits & wifi_connected_bit) == 0) {
        if (wifi_callback_error) |err| return err;
        return error.WifiConnectionFailed;
    }

    log.info("Wi-Fi connected; IP: {}.{}.{}.{}", .{
        @as(u8, @truncate(wifi_ip_addr)),
        @as(u8, @truncate(wifi_ip_addr >> 8)),
        @as(u8, @truncate(wifi_ip_addr >> 16)),
        @as(u8, @truncate(wifi_ip_addr >> 24)),
    });
}

export fn onWifiEvent(
    _: ?*anyopaque,
    _: sys.esp_event_base_t,
    event_id: i32,
    _: ?*anyopaque,
) callconv(.c) void {
    switch (event_id) {
        sys.WIFI_EVENT_STA_START => idf.wifi.connect() catch |err| {
            wifi_callback_error = err;
            _ = sys.xEventGroupSetBits(wifi_event_group, wifi_failed_bit);
        },
        sys.WIFI_EVENT_STA_DISCONNECTED => {
            if (wifi_retry_count < max_wifi_retries) {
                wifi_retry_count += 1;
                idf.wifi.connect() catch |err| {
                    wifi_callback_error = err;
                    _ = sys.xEventGroupSetBits(wifi_event_group, wifi_failed_bit);
                };
            } else {
                _ = sys.xEventGroupSetBits(wifi_event_group, wifi_failed_bit);
            }
        },
        else => {},
    }
}

export fn onIpEvent(
    _: ?*anyopaque,
    _: sys.esp_event_base_t,
    event_id: i32,
    event_data: ?*anyopaque,
) callconv(.c) void {
    if (event_id != sys.IP_EVENT_STA_GOT_IP) return;

    const event = @as(*sys.ip_event_got_ip_t, @ptrCast(@alignCast(event_data)));
    const ip = event.ip_info.ip.addr;
    wifi_ip_addr = ip;
    wifi_retry_count = 0;
    _ = sys.xEventGroupSetBits(wifi_event_group, wifi_connected_bit);
}

fn copyZ(dest: []u8, src: []const u8) void {
    const len = @min(dest.len - 1, src.len);
    @memcpy(dest[0..len], src[0..len]);
    dest[len] = 0;
}

const log = std.log.scoped(idf.log.default_log_scope);

pub const panic = idf.esp_panic.panic;
pub const std_options: std.Options = .{
    .log_level = .info,
    .logFn = idf.log.espLogFn,
};
