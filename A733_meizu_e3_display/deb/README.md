# Meizu E3 DEB：两条构建路线

```text
deb/
├── mainline/
│   ├── 01_original_package/
│   ├── 02_driver_integration/
│   └── 03_official_graph_package/
└── codexline/
    └── 01_nonburst_package/
```

每个阶段内部再分为：

- `packages/`：生成的 DEB 或构建归档。
- `src/`：解包、staging 和实际打包源码。

## Mainline

### `01_original_package`

原始 `0.1.6` 包及解包源码，是后续驱动修改的基础。

```text
68905732276f644ba93218f7d4197f73eb200d4f6be4c4b45bf7440b78a4bfec  meizu-e3-dkms_0.1.6_all.deb
```

### `02_driver_integration`

`0.1.7`、`0.1.8` 驱动和安装流程迭代。主要涉及 SEC 触摸、SGM37604A 背光、DKMS 和桌面触摸映射等集成工作；尚未形成后来的官方 graph 版 overlay。

```text
af3dc37981d7f07816de67b1c50948d0d72f07302bc83e3b1de117fd420b5f80  meizu-e3-dkms_0.1.7_all.deb
360996af0cce2a1d89ee69da4e98c5fb53643bca1d4e3c0423cb9227718a1f10  meizu-e3-dkms_0.1.8_all.deb
```

### `03_official_graph_package`

`0.1.9` 在最初 overlay 基础上加入官方 A7A `dsi0 port@1 reg = <1>` graph 修正，属于 Mainline 的首次受控验证包。

```text
992d1cba7de359b2baa736a8e5a65ad2978804bf46c6b2d54002c011e23aedd0  meizu-e3-dkms_0.1.9_all.deb
```

`meizu-e3-dkms_0.1.9_initial-test-copy.deb` 是首次实验现场副本，与主包 SHA-256 相同。

## Codexline

### `01_nonburst_package`

`0.1.10` 是 Codexline non-burst 假设对应的包：描述和源码明确将 DSI flags 从 burst 路径改为 non-burst，同时保留官方 `port@1 reg = <1>`。该包没有修复旧内核 hard lock，因此不作为 Mainline 的最终 overlay。

```text
998700ce97de18ae5fc07a754151c7d9893ef885b5abe83342af83e2191476d9  meizu-e3-dkms_0.1.10_all.deb
```

后续旧内核严格单 DSI 测试只复用了 `0.1.10` 中已经验证的 SGM37604A 背光源码，并没有采用 non-burst overlay；因此包按产生原因归入 Codexline，复用关系在相应 Mainline 实验 README 中注明。
