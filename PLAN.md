把tex4ht、algorithm文件删掉；

最终各个包的职责：

- html：让任意quarto项目（qmd + latex block + sty/cls template）能输出流畅的html格式
  - ref：让tbl、sec、fig等由quarto内部消费的语法也能支持`\ref`命令
  - parse：解析任意latex block（tables可被pandoc识别，单独处理，和管道表格式对齐；其他块用lwarp解析成html；counters处理自定义块的`label`计数问题，并支持`ref`引用）

- pdf：让任意latex模板结合自己写的qmd文件就能马上编译