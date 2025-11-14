# IPABuil

它是用来构建IPA，并具备以下功能：
1. 自动选择最新并有效的描述文件。
2. 校验描述文件以及证书有效性。
3. 输出描述文件和证书的一些信息。

## 打包为 DMG

在仓库根目录执行脚本即可生成 Release 版 DMG：

```bash
Scripts/build-dmg.sh
```

脚本会调用 `xcodebuild` 完成 Release 构建，并把应用拷贝到 `dist/DMGStage`，最后通过 `hdiutil` 生成 `dist/certificate-manager.dmg` 以供分发。
