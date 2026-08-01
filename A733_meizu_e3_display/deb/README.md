# Meizu E3 DEB：按测试路线归档

> 先阅读 [`SOLUTION_TIMELINE.md`](SOLUTION_TIMELINE.md)。外层目录与 `test_files/mainline`、`test_files/codexline` 的实验编号和名称对应，不再按 DEB 的 `0.1.x` 版本号排列。

```text
deb/
├── mainline/
│   ├── 00_package_foundation/
│   │   ├── 01_original_package/
│   │   └── 02_driver_integration/
│   ├── 01_initial_overlay_validation/
│   └── 03_new_kernel_overlay_validation/
└── codexline/
    ├── 01_nonburst_dsi_experiment/
    └── 02_rk_reference_pushpull_validation/
```

外层编号表达测试阶段。`00_package_foundation` 是实验开始前的包和驱动基础；它内部的 `01`、`02` 只表达包的历史演化，不参与两条测试路线的编号。

实际文件名、staging 目录和 Debian `Version` 字段仍保留 `0.1.6`～`0.1.10`。这些是包管理所需的真实版本，不再承担外层目录排序含义。

有实际构建产物的阶段内部再分为：

- `packages/`：生成的 DEB 或构建归档。
- `src/`：解包、staging 和实际打包源码。

只有 README 的目录表示该实验阶段没有生成并验证独立 DEB，用于防止把其他阶段的包误认为该实验的产物。

## Mainline

### `00_package_foundation/01_original_package`

原始 `0.1.6` 包及解包源码，是后续驱动修改的基础，不是一次显示验证实验。

```text
68905732276f644ba93218f7d4197f73eb200d4f6be4c4b45bf7440b78a4bfec  meizu-e3-dkms_0.1.6_all.deb
```

### `00_package_foundation/02_driver_integration`

`0.1.7`、`0.1.8` 驱动和安装流程迭代。主要涉及 SEC 触摸、SGM37604A 背光、DKMS 和桌面触摸映射等集成工作；尚未形成后来的官方 graph 版 overlay。

```text
af3dc37981d7f07816de67b1c50948d0d72f07302bc83e3b1de117fd420b5f80  meizu-e3-dkms_0.1.7_all.deb
360996af0cce2a1d89ee69da4e98c5fb53643bca1d4e3c0423cb9227718a1f10  meizu-e3-dkms_0.1.8_all.deb
```

### `01_initial_overlay_validation`

对应 `test_files/mainline/01_initial_overlay_validation`。其中 `0.1.9` 在最初 overlay 基础上加入官方 A7A `dsi0 port@1 reg = <1>` graph 修正，是 Mainline 的首次受控验证包。

```text
992d1cba7de359b2baa736a8e5a65ad2978804bf46c6b2d54002c011e23aedd0  meizu-e3-dkms_0.1.9_all.deb
```

`meizu-e3-dkms_0.1.9_initial-test-copy.deb` 是首次实验现场副本，与主包 SHA-256 相同。

### `03_new_kernel_overlay_validation`

对应最终稳定的 T4/6.6 验证阶段。该阶段重新采用 `reg = <1>` 的官方 graph 方向，并移植背光、触摸驱动，但没有生成和验证新的最终一体化 DEB；目录中只保留这一事实说明。

## Codexline

### `01_nonburst_dsi_experiment`

对应 `test_files/codexline/01_nonburst_dsi_experiment`。其中 `0.1.10` 将 DSI flags 从 burst 改为 non-burst，同时保留官方 `port@1 reg = <1>`。该实验没有修复旧内核 hard lock，已被否定，不是最终推荐包。

```text
998700ce97de18ae5fc07a754151c7d9893ef885b5abe83342af83e2191476d9  meizu-e3-dkms_0.1.10_all.deb
```

后续旧内核严格单 DSI 测试只复用了 `0.1.10` 中已经验证的 SGM37604A 背光源码，并没有采用 non-burst overlay。

### `02_rk_reference_pushpull_validation`

对应 `test_files/codexline/02_rk_reference_pushpull_validation`。该组合实验只保存 overlay、源码、脚本和日志，没有生成独立 DEB；push-pull 假设也没有成为最终方案。
