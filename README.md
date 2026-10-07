# PKU-Replay-Fix

一个简单的 Windows 小工具，用于批量将课程录播 `.ts` 文件无损转换为 `.mp4`。

主要用于修复部分 HLS 录播直接拼接为 TS 后出现的周期性卡顿、断音等问题。程序通过 FFmpeg 对 TS 进行重新封装，不重新编码视频或音频，因此转换速度较快，也不会损失画质或音质。

## 功能

- 批量处理当前文件夹中的所有 `.ts`，无损转换为 `.mp4`
- 运行时显示当前文件和总体转换进度
- 转换成功后删除原 `.ts`
- 自动检测 FFmpeg，未安装时会自动安装

## 安装和使用

仅支持 Windows。

下载仓库中的：

```text
PKU-Replay-Fix.cmd
```

将此程序放到需要转换的 `.ts` 录播文件所在文件夹，例如：

```text
录播文件夹\
├─ PKU-Art-TS-to-MP4-OneFile-Fixed.cmd
├─ 第一讲.ts
├─ 第二讲.ts
└─ 第三讲.ts
```

双击：

```text
PKU-Art-TS-to-MP4-OneFile-Fixed.cmd
```

首次运行时，如果电脑中没有 FFmpeg，程序会询问是否自动安装。选择“是”后，会通过 Windows Package Manager (`winget`) 安装 FFmpeg。

如果系统没有 `winget`，需要先手动安装 FFmpeg。

程序会自动扫描当前文件夹，并依次转换所有 `.ts`。

转换完成后：

```text
第一讲.mp4
第二讲.mp4
第三讲.mp4
```

转换成功且通过验证的 `.ts` 会自动删除；如果转换失败、取消任务或遇到不兼容的文件，原 `.ts` 会保留。

## 说明

本工具使用 FFmpeg 的 stream copy 模式进行重新封装：

```text
TS → H.264 / AAC → MP4
```

不会重新编码音视频。

对于常见的 H.264 + AAC 教学录播可以直接使用；如果 TS 中包含 MP4 不支持直接封装的编码格式，程序会停止处理该文件并保留原文件。

## License

本项目仅用于学习和个人课程录播文件整理。
