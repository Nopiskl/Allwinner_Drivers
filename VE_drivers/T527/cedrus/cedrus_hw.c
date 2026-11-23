// SPDX-License-Identifier: GPL-2.0
/*
 * Cedrus VPU driver
 *
 * Copyright (C) 2016 Florent Revest <florent.revest@free-electrons.com>
 * Copyright (C) 2018 Paul Kocialkowski <paul.kocialkowski@bootlin.com>
 * Copyright (C) 2018 Bootlin
 *
 * Based on the vim2m driver, that is:
 *
 * Copyright (c) 2009-2010 Samsung Electronics Co., Ltd.
 * Pawel Osciak, <pawel@osciak.com>
 * Marek Szyprowski, <m.szyprowski@samsung.com>
 */

#include <linux/platform_device.h>
#include <linux/of_reserved_mem.h>
#include <linux/of_device.h>
#include <linux/dma-mapping.h>
#include <linux/interrupt.h>
#include <linux/clk.h>
#include <linux/pm_runtime.h>
#include <linux/regmap.h>
#include <linux/reset.h>
#include <linux/soc/sunxi/sunxi_sram.h>
#include <sunxi-iommu.h>

#include <media/videobuf2-core.h>
#include <media/v4l2-mem2mem.h>

#include "cedrus.h"
#include "cedrus_hw.h"
#include "cedrus_regs.h"

int cedrus_engine_enable(struct cedrus_ctx *ctx, enum cedrus_codec codec)
{
	u32 reg = 0;

	/*
	 * FIXME: This is only valid on 32-bits DDR's, we should test
	 * it on the A13/A33.
	 */
	reg |= VE_MODE_REC_WR_MODE_2MB;
	reg |= VE_MODE_DDR_MODE_BW_128;

	switch (codec) {
	case CEDRUS_CODEC_MPEG2:
		reg |= VE_MODE_DEC_MPEG;
		break;

	/* H.264 and VP8 both use the same decoding mode bit. */
	case CEDRUS_CODEC_H264:
	case CEDRUS_CODEC_VP8:
		reg |= VE_MODE_DEC_H264;
		break;

	case CEDRUS_CODEC_H265:
		reg |= VE_MODE_DEC_H265;
		break;

	default:
		return -EINVAL;
	}

	if (ctx->src_fmt.width == 4096)
		reg |= VE_MODE_PIC_WIDTH_IS_4096;
	if (ctx->src_fmt.width > 2048)
		reg |= VE_MODE_PIC_WIDTH_MORE_2048;

	cedrus_write(ctx->dev, VE_MODE, reg);

	return 0;
}

void cedrus_engine_disable(struct cedrus_dev *dev)
{
	cedrus_write(dev, VE_MODE, VE_MODE_DISABLED);
}

void cedrus_dst_format_set(struct cedrus_dev *dev,
			   struct v4l2_pix_format *fmt)
{
	unsigned int width = fmt->width;
	unsigned int height = fmt->height;
	u32 chroma_size;
	u32 reg;

	switch (fmt->pixelformat) {
	case V4L2_PIX_FMT_NV12:
		chroma_size = ALIGN(width, 16) * ALIGN(height, 16) / 2;

		/* Set both PRIMARY (output write) and SECONDARY_OUT_FMT_EXT
		 * (used for inter-frame ref read) to NV12 so the format the
		 * HW writes the reconstructed frame in matches what it later
		 * reads as a reference. Without this, secondary defaults to
		 * TILED_32 -> ref reads interpret NV12 storage as tiled =
		 * garbage motion comp on all P/B frames.
		 */
		reg = VE_PRIMARY_OUT_FMT_NV12 | VE_SECONDARY_OUT_FMT_EXT_NV12;
		cedrus_write(dev, VE_PRIMARY_OUT_FMT, reg);

		/* CHROMA_BUF_LEN: bits 31..30 select SECONDARY format.
		 * Set to EXT to point at the EXT bits we set above, OR
		 * the chroma buf length in bits 27..0.
		 */
		reg = (chroma_size / 2) | VE_SECONDARY_OUT_FMT_EXT;
		cedrus_write(dev, VE_CHROMA_BUF_LEN, reg);

		reg = chroma_size / 2;
		cedrus_write(dev, VE_PRIMARY_CHROMA_BUF_LEN, reg);

		reg = VE_PRIMARY_FB_LINE_STRIDE_LUMA(ALIGN(width, 16)) |
		      VE_PRIMARY_FB_LINE_STRIDE_CHROMA(ALIGN(width, 16) / 2);
		cedrus_write(dev, VE_PRIMARY_FB_LINE_STRIDE, reg);

		break;
	case V4L2_PIX_FMT_SUNXI_TILED_NV12:
	default:
		chroma_size = ALIGN(width, 16) * ALIGN(height, 16) / 2;

		reg = VE_PRIMARY_OUT_FMT_TILED_32_NV12;
		cedrus_write(dev, VE_PRIMARY_OUT_FMT, reg);

		reg = VE_SECONDARY_OUT_FMT_TILED_32_NV12 |
		      VE_CHROMA_BUF_LEN_SDRT(chroma_size / 2);
		cedrus_write(dev, VE_CHROMA_BUF_LEN, reg);

		cedrus_write(dev, VE_PRIMARY_CHROMA_BUF_LEN, chroma_size / 2);

		reg = VE_PRIMARY_FB_LINE_STRIDE_LUMA(ALIGN(width, 16)) |
		      VE_PRIMARY_FB_LINE_STRIDE_CHROMA(ALIGN(width, 16));
		cedrus_write(dev, VE_PRIMARY_FB_LINE_STRIDE, reg);

		break;
	}
}

static irqreturn_t cedrus_irq(int irq, void *data)
{
	struct cedrus_dev *dev = data;
	struct cedrus_ctx *ctx;
	enum vb2_buffer_state state;
	enum cedrus_irq_status status;

	ctx = v4l2_m2m_get_curr_priv(dev->m2m_dev);
	if (!ctx) {
		v4l2_err(&dev->v4l2_dev,
			 "Instance released before the end of transaction\n");
		return IRQ_NONE;
	}

	status = dev->dec_ops[ctx->current_codec]->irq_status(ctx);
	if (status == CEDRUS_IRQ_NONE)
		return IRQ_NONE;

	dev->dec_ops[ctx->current_codec]->irq_disable(ctx);
	dev->dec_ops[ctx->current_codec]->irq_clear(ctx);

	if (status == CEDRUS_IRQ_ERROR)
		state = VB2_BUF_STATE_ERROR;
	else
		state = VB2_BUF_STATE_DONE;

	/*
	 * Complete the request AFTER HW finishes, so userspace poll
	 * returns POLLPRI only once the frame is actually decoded.
	 * This prevents the next frame's device_run from overwriting
	 * VE registers while the current frame is still in progress.
	 */
	if (ctx->current_req)
		v4l2_ctrl_request_complete(ctx->current_req, &ctx->hdl);
	ctx->current_req = NULL;

	v4l2_m2m_buf_done_and_job_finish(ctx->dev->m2m_dev, ctx->fh.m2m_ctx,
					 state);

	return IRQ_HANDLED;
}

int cedrus_hw_suspend(struct device *device)
{
	struct cedrus_dev *dev = dev_get_drvdata(device);

	clk_disable_unprepare(dev->ram_clk);
	clk_disable_unprepare(dev->mod_clk);
	clk_disable_unprepare(dev->ahb_clk);

	reset_control_assert(dev->rstc);

	return 0;
}

int cedrus_hw_resume(struct device *device)
{
	struct cedrus_dev *dev = dev_get_drvdata(device);
	int ret;

	ret = reset_control_reset(dev->rstc);
	if (ret) {
		dev_err(dev->dev, "Failed to apply reset\n");

		return ret;
	}

	ret = clk_prepare_enable(dev->ahb_clk);
	if (ret) {
		dev_err(dev->dev, "Failed to enable AHB clock\n");

		goto err_rst;
	}

	ret = clk_prepare_enable(dev->mod_clk);
	if (ret) {
		dev_err(dev->dev, "Failed to enable MOD clock\n");

		goto err_ahb_clk;
	}

	ret = clk_prepare_enable(dev->ram_clk);
	if (ret) {
		dev_err(dev->dev, "Failed to enable RAM clock\n");

		goto err_mod_clk;
	}

	return 0;

err_mod_clk:
	clk_disable_unprepare(dev->mod_clk);
err_ahb_clk:
	clk_disable_unprepare(dev->ahb_clk);
err_rst:
	reset_control_assert(dev->rstc);

	return ret;
}

int cedrus_hw_probe(struct cedrus_dev *dev)
{
	const struct cedrus_variant *variant;
	int irq_dec;
	int ret;

	variant = of_device_get_match_data(dev->dev);
	if (!variant)
		return -EINVAL;

	dev->capabilities = variant->capabilities;

	irq_dec = platform_get_irq(dev->pdev, 0);
	if (irq_dec <= 0)
		return irq_dec;
	ret = devm_request_irq(dev->dev, irq_dec, cedrus_irq,
			       0, dev_name(dev->dev), dev);
	if (ret) {
		dev_err(dev->dev, "Failed to request IRQ\n");

		return ret;
	}

	ret = of_reserved_mem_device_init(dev->dev);
	if (ret && ret != -ENODEV) {
		dev_err(dev->dev, "Failed to reserve memory\n");

		return ret;
	}

	if (!(dev->capabilities & CEDRUS_CAPABILITY_NO_SRAM)) {
		ret = sunxi_sram_claim(dev->dev);
		if (ret) {
			dev_err(dev->dev, "Failed to claim SRAM\n");

			goto err_mem;
		}
	}

	dev->ahb_clk = devm_clk_get(dev->dev, "ahb");
	if (IS_ERR(dev->ahb_clk)) {
		dev_err(dev->dev, "Failed to get AHB clock\n");

		ret = PTR_ERR(dev->ahb_clk);
		goto err_sram;
	}

	dev->mod_clk = devm_clk_get(dev->dev, "mod");
	if (IS_ERR(dev->mod_clk)) {
		dev_err(dev->dev, "Failed to get MOD clock\n");

		ret = PTR_ERR(dev->mod_clk);
		goto err_sram;
	}

	dev->ram_clk = devm_clk_get(dev->dev, "ram");
	if (IS_ERR(dev->ram_clk)) {
		dev_err(dev->dev, "Failed to get RAM clock\n");

		ret = PTR_ERR(dev->ram_clk);
		goto err_sram;
	}

	dev->rstc = devm_reset_control_get(dev->dev, NULL);
	if (IS_ERR(dev->rstc)) {
		dev_err(dev->dev, "Failed to get reset control\n");

		ret = PTR_ERR(dev->rstc);
		goto err_sram;
	}

	dev->base = devm_platform_ioremap_resource(dev->pdev, 0);
	if (IS_ERR(dev->base)) {
		dev_err(dev->dev, "Failed to map registers\n");

		ret = PTR_ERR(dev->base);
		goto err_sram;
	}

	{
		/* (M14) Optional VE mod clock override via cedrus.clk_hz module
		 * param — exported from cedrus.c. 0 = use variant default
		 * (600 MHz on T527). Lets us validate the silicon ceiling
		 * without recompiling. */
		extern unsigned long cedrus_clk_hz_override;
		unsigned long rate = cedrus_clk_hz_override ?
				     cedrus_clk_hz_override :
				     variant->mod_rate;

		ret = clk_set_rate(dev->mod_clk, rate);
		if (ret) {
			dev_err(dev->dev,
				"Failed to set VE clock rate %lu Hz: %d\n",
				rate, ret);
			goto err_sram;
		}
		dev_info(dev->dev,
			 "VE mod clock requested %lu Hz, got %lu Hz%s\n",
			 rate, clk_get_rate(dev->mod_clk),
			 cedrus_clk_hz_override ? " (clk_hz override)" : "");
	}

	pm_runtime_enable(dev->dev);
	if (!pm_runtime_enabled(dev->dev)) {
		ret = cedrus_hw_resume(dev->dev);
		if (ret)
			goto err_pm;
	}

	/* T527 VE has two MBUS masters: VE_MBUS0 (master 2) for output DMA
	 * writes, VE_MBUS1 (master 3) for MC reference reads. DTS iommus
	 * property binds only master 2 (sunxi_iommu_of_xlate stores one master
	 * per device). Explicitly enable master 3 so MC reads are translated. */
	sunxi_enable_device_iommu(3, true);

	return 0;

err_pm:
	pm_runtime_disable(dev->dev);
err_sram:
	sunxi_sram_release(dev->dev);
err_mem:
	of_reserved_mem_device_release(dev->dev);

	return ret;
}

void cedrus_hw_remove(struct cedrus_dev *dev)
{
	sunxi_enable_device_iommu(3, false);
	pm_runtime_disable(dev->dev);
	if (!pm_runtime_status_suspended(dev->dev))
		cedrus_hw_suspend(dev->dev);

	sunxi_sram_release(dev->dev);

	of_reserved_mem_device_release(dev->dev);
}
