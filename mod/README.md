# SHENZHEN I/O GUI Scale Mod (macOS)

这是对 SHENZHEN I/O 的 `Shenzhen.exe` 做 IL 补丁的进程内 mod。它不是系统级放大镜，也不依赖外部截屏工具。

## 用法

1. 完全退出游戏。
2. 双击 `apply-2x.command`，或打开终端运行：

   ```bash
   ./apply.command 2
   ```

   倍率支持 `1`、`2`、`3`、`4`，默认 `2`。

3. 从 Steam 正常启动 SHENZHEN I/O。

补丁会改写游戏目录里的 `Shenzhen.exe`，并保留：

- `Shenzhen.exe.scale-original`：原始文件
- `Shenzhen.exe.scale-patched.sha256`：已打补丁文件的哈希

## 还原

双击 `restore.command`，或运行：

```bash
./restore.command
```

## 补丁原理

源码中的关键位置：

- `GameLogic.CreateWindow(...)`：约 `GameLogic.cs:9186`
- `SDL_CreateWindow(...)`：约 `GameLogic.cs:9205`
- `Renderer.Init(...)`：约 `GameLogic.cs:9207`
- `Window.SetFullscreen(...)`：约 `--qG2Vhtoy9BS5nEz9KChZWFw--.cs:115`

补丁器使用 Mono.Cecil 改写 IL：

1. 把 `CreateWindow` 收到的 width/height 按倍率缩小；
2. 在 `SDL_CreateWindow` 之后强制 `SDL_SetWindowFullscreen(window, 4097)`；
3. 同步缩小 Renderer 的初始化尺寸和 resize 尺寸。

这样游戏以较低内部渲染分辨率绘制，再由 macOS 全屏放大，整屏文字和 UI 会变大。

## 注意

- 当前补丁器是 macOS arm64 自包含程序。
- 只针对当前 Steam 版本的 SHENZHEN I/O；游戏更新后重新运行 `apply.command`。
- 如果源码结构变化导致找不到注入点，补丁器会报错并且不会覆盖原游戏文件。
- 安装补丁前，游戏会把窗口分辨率写回 `config.cfg`。测试期间当前机器上的配置被游戏改成过 `Fullscreen=True`、`2336x1510`。需要恢复时运行 `./restore-config.command`，它会用本目录里的 `config-original.cfg` 覆盖。
