// SPDX-License-Identifier: GPL-2.0-or-later
/* Copyright(c) 2020 - 2026 Allwinner Technology Co.,Ltd. */
/*
 * ST7789V-compatible P169H002-CTP 240x280 panel support.
 *
 * The initialization values are based on the supplied ST7789P3 + BOE table.
 * GATECTRL.NL is corrected from 288 to 280 gate lines for P169H002-CTP.
 * Revision r4 was validated on the physical panel with full top/bottom coverage.
 */

#include "st7789v_240x280.h"

#define ST7789V_X_OFFSET	0
#define ST7789V_Y_OFFSET	0
#define ST7789V_MAX_INIT_DATA	14
#define ST7789V_DRIVER_REV	"vendor-seq-20260814-r4-y0-nl280"
#define RESET(sel, value) sunxi_lcd_gpio_set_value(sel, 0, value)

struct st7789v_init_entry {
	u8 cmd;
	u8 len;
	u8 data[ST7789V_MAX_INIT_DATA];
};

static const struct st7789v_init_entry st7789v_vendor_init[] = {
	{ 0x36, 1, { 0x00 } },
	{ 0x3a, 1, { 0x05 } },
	{ 0xb2, 5, { 0x0c, 0x0c, 0x00, 0x33, 0x33 } },
	{ 0xb7, 1, { 0x05 } },
	{ 0xbb, 1, { 0x21 } },
	{ 0xc0, 1, { 0x2c } },
	{ 0xc2, 1, { 0x01 } },
	{ 0xc3, 1, { 0x15 } },
	{ 0xc6, 1, { 0x0f } },
	/* The supplier file contains both D0 writes; retain both for this test. */
	{ 0xd0, 1, { 0xa7 } },
	{ 0xd0, 2, { 0xa4, 0xa1 } },
	{ 0xd6, 1, { 0xa1 } },
	{ 0xe0, 14, { 0xf0, 0x05, 0x0e, 0x08, 0x0a, 0x17, 0x39,
			 0x54, 0x4e, 0x37, 0x12, 0x12, 0x31, 0x37 } },
	{ 0xe1, 14, { 0xf0, 0x10, 0x14, 0x0d, 0x0b, 0x05, 0x39,
			 0x44, 0x4d, 0x38, 0x14, 0x14, 0x2e, 0x35 } },
	/* NL=0x22 selects 280 gate lines; SCN=0 starts at Gate 0. */
	{ 0xe4, 3, { 0x22, 0x00, 0x00 } },
};

static void st7789v_power_on(u32 sel);
static void st7789v_power_off(u32 sel);
static void st7789v_backlight_open(u32 sel);
static void st7789v_backlight_close(u32 sel);
static void st7789v_panel_init(u32 sel);
static void st7789v_panel_exit(u32 sel);

static int st7789v_write(u32 sel, u8 cmd, const u8 *data, u32 len)
{
	u32 i;
	int ret;

	ret = sunxi_lcd_cmd_write(sel, cmd);
	if (ret) {
		LCDFB_WRN("ST7789 write command 0x%02x failed: %d\n", cmd, ret);
		return ret;
	}

	for (i = 0; i < len; i++) {
		ret = sunxi_lcd_para_write(sel, data[i]);
		if (ret) {
			LCDFB_WRN("ST7789 command 0x%02x parameter %u failed: %d\n",
				  cmd, i, ret);
			return ret;
		}
	}

	return 0;
}

static int st7789v_set_address(u32 sel, u16 x_start, u16 y_start,
			       u16 x_end, u16 y_end)
{
	u8 column[4];
	u8 row[4];
	int ret;

	x_start += ST7789V_X_OFFSET;
	x_end += ST7789V_X_OFFSET;
	y_start += ST7789V_Y_OFFSET;
	y_end += ST7789V_Y_OFFSET;

	column[0] = x_start >> 8;
	column[1] = x_start & 0xff;
	column[2] = x_end >> 8;
	column[3] = x_end & 0xff;
	row[0] = y_start >> 8;
	row[1] = y_start & 0xff;
	row[2] = y_end >> 8;
	row[3] = y_end & 0xff;

	ret = st7789v_write(sel, 0x2a, column, ARRAY_SIZE(column));
	if (ret)
		return ret;

	return st7789v_write(sel, 0x2b, row, ARRAY_SIZE(row));
}

static void st7789v_panel_init(u32 sel)
{
	struct sunxi_lcd_fb_disp_panel_para info;
	u32 i;
	int ret;

	memset(&info, 0, sizeof(info));
	if (sunxi_lcd_fb_bsp_disp_get_panel_info(sel, &info)) {
		LCDFB_WRN("get panel info fail!\n");
		return;
	}

	if (info.lcd_x != 240 || info.lcd_y != 280)
		LCDFB_WRN("expected 240x280, got %ux%u\n",
			  info.lcd_x, info.lcd_y);

	LCDFB_NOTE("ST7789 init %s start: %ux%u, pixel_fmt=%u\n",
		   ST7789V_DRIVER_REV, info.lcd_x, info.lcd_y,
		   info.lcd_pixel_fmt);
	if (info.lcd_pixel_fmt != LCDFB_FORMAT_RGB_565)
		LCDFB_WRN("supplier sequence requires RGB565/MADCTL=0x00, pixel_fmt=%u\n",
			  info.lcd_pixel_fmt);

	/* Sleep out must be followed by at least 120 ms delay. */
	ret = st7789v_write(sel, 0x11, NULL, 0);
	if (ret)
		goto init_failed;
	sunxi_lcd_delay_ms(120);

	for (i = 0; i < ARRAY_SIZE(st7789v_vendor_init); i++) {
		ret = st7789v_write(sel, st7789v_vendor_init[i].cmd,
				     st7789v_vendor_init[i].data,
				     st7789v_vendor_init[i].len);
		if (ret)
			goto init_failed;
	}

	ret = st7789v_write(sel, 0x21, NULL, 0); /* Display inversion on */
	if (ret)
		goto init_failed;

	/* E4 configures 280 gates from Gate 0, so visible GRAM is 0..279. */
	ret = st7789v_set_address(sel, 0, 0, info.lcd_x - 1,
				    info.lcd_y - 1);
	if (ret)
		goto init_failed;

	ret = st7789v_write(sel, 0x29, NULL, 0); /* Display on */
	if (ret)
		goto init_failed;
	ret = st7789v_write(sel, 0x2c, NULL, 0); /* Memory write */
	if (ret)
		goto init_failed;

	LCDFB_NOTE("ST7789 init %s complete\n", ST7789V_DRIVER_REV);
	return;

init_failed:
	LCDFB_WRN("ST7789 init %s aborted: %d\n", ST7789V_DRIVER_REV, ret);
}

static void st7789v_panel_exit(u32 sel)
{
	sunxi_lcd_cmd_write(sel, 0x28); /* Display off */
	sunxi_lcd_delay_ms(20);
	sunxi_lcd_cmd_write(sel, 0x10); /* Sleep in */
	sunxi_lcd_delay_ms(120);

	RESET(sel, 0);
	sunxi_lcd_delay_ms(10);
	sunxi_lcd_pin_cfg(sel, 0);
}

static s32 st7789v_open_flow(u32 sel)
{
	LCD_OPEN_FUNC(sel, st7789v_power_on, 50);
	LCD_OPEN_FUNC(sel, st7789v_panel_init, 20);
	LCD_OPEN_FUNC(sel, sunxi_lcd_fb_black_screen, 50);
	LCD_OPEN_FUNC(sel, st7789v_backlight_open, 0);
	return 0;
}

static s32 st7789v_close_flow(u32 sel)
{
	LCD_CLOSE_FUNC(sel, st7789v_backlight_close, 20);
	LCD_CLOSE_FUNC(sel, st7789v_panel_exit, 10);
	LCD_CLOSE_FUNC(sel, st7789v_power_off, 10);
	return 0;
}

static void st7789v_power_on(u32 sel)
{
	sunxi_lcd_power_enable(sel, 0);
	sunxi_lcd_pin_cfg(sel, 1);

	RESET(sel, 1);
	sunxi_lcd_delay_ms(100);
	RESET(sel, 0);
	sunxi_lcd_delay_ms(100);
	RESET(sel, 1);
	sunxi_lcd_delay_ms(120);
}

static void st7789v_power_off(u32 sel)
{
	sunxi_lcd_power_disable(sel, 0);
}

static void st7789v_backlight_open(u32 sel)
{
	sunxi_lcd_pwm_enable(sel);
	sunxi_lcd_backlight_enable(sel);
}

static void st7789v_backlight_close(u32 sel)
{
	sunxi_lcd_backlight_disable(sel);
	sunxi_lcd_pwm_disable(sel);
}

static int st7789v_blank(u32 sel, u32 enable)
{
	return st7789v_write(sel, enable ? 0x28 : 0x29, NULL, 0);
}

static int st7789v_set_var(u32 sel, struct fb_info *info)
{
	return 0;
}

static int st7789v_set_addr_win(u32 sel, int x_start, int y_start,
				int x_end, int y_end)
{
	int ret;

	ret = st7789v_set_address(sel, x_start, y_start, x_end, y_end);
	if (ret)
		return ret;

	return st7789v_write(sel, 0x2c, NULL, 0);
}

struct __lcd_panel st7789v_240x280_panel = {
	.name = "st7789v_240x280",
	.func = {
		.cfg_open_flow = st7789v_open_flow,
		.cfg_close_flow = st7789v_close_flow,
		.blank = st7789v_blank,
		.set_var = st7789v_set_var,
		.set_addr_win = st7789v_set_addr_win,
	},
};
