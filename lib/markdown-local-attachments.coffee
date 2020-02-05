{CompositeDisposable} = require 'atom'
{dirname, basename, extname, join} = require 'path'
clipboard = require 'clipboard'
fs = require 'fs'


module.exports =
    subscriptions : null

    activate : ->
      @subscriptions = new CompositeDisposable
      @subscriptions.add atom.commands.add 'atom-workspace',
            'markdown-local-attachments:attach-file' : => @attachFile()
      @subscriptions.add atom.commands.add 'atom-workspace',
            'markdown-local-attachments:delete-file' : => @deleteFile()

    deactivate : ->
        @subscriptions.dispose()

    attachFile : ->
        try
          if !cursor = atom.workspace.getActiveTextEditor() then return

          position = cursor.getCursorBufferPosition()

          # 文件类型检测
          if !(cursor.getGrammar() and cursor.getPath() and (cursor.getPath().substr(-3) == '.md' or cursor.getPath().substr(-9) == '.markdown') and cursor.getGrammar().scopeName == 'source.gfm')
              # 保证文本黏贴正常使用
              text = clipboard.readText()
              if(text)
                  cursor.insertText(text)
                  return


          # clipboard扩展读取文件路径
          # windows系统
          rawFilePath = clipboard.read('FileNameW')
          filePath = rawFilePath.replace(new RegExp(String.fromCharCode(0), 'g'), '')
          if !fs.existsSync filePath
              # mac系统
              filePath = decodeURI(clipboard.read('public.file-url').replace('file://', ''))

          if fs.existsSync filePath
              # 文件作为附件插入
              filenameRaw = basename(filePath)
              filename = encodeURI(filenameRaw)

              # 设定文件存放子目录
              curDirectory = dirname(cursor.getPath())
              # Join adds a platform independent directory separator
              fullname = join(curDirectory, filename)
    
              subFolderToUse = ""
              if atom.config.get 'markdown-local-attachments.use_subfolder'
                # 根据设置获取子目录文件名
                subFolderToUse = atom.config.get 'markdown-local-attachments.subfolder'
                if subFolderToUse != ""
                  assetsDirectory = join(curDirectory, subFolderToUse)
                  # 如果子目录不存在则创建之
                  if !fs.existsSync assetsDirectory
                    fs.mkdirSync assetsDirectory
                  # 文件完整路径名
                  fullname = join(assetsDirectory, filename)
    
              # 复制文件
              fs.copyFileSync filePath, fullname

              # markdown文件链接代码生成
              text = '[' + filenameRaw + ']('
              text += join(subFolderToUse, filename) + ')'

          else
              # clipboard扩展读取粘贴板图片内容
              img = clipboard.readImage()
              # 空内容处理
              if img.isEmpty()
                  # 保证文本黏贴正常使用
                  text = clipboard.readText()
                  if(text)
                      cursor.insertText(text)
                      return

              else
                  # 图片作为附件插入
            
                  filenamecandidate = atom.workspace.getActiveTextEditor().getSelectedText()
                  # 检测选中区域是否可以构成文件名
                  filenamePattern = /// ^[0-9a-zA-Z-_]+$ ///
                  if filenamecandidate.match filenamePattern
                      filenameRaw = filenamecandidate
                  else
                      filenameRaw = new Date().format()
                  filenameRaw += ".png"
                  filename = encodeURI(filenameRaw)

                  # 设定文件存放子目录
                  curDirectory = dirname(cursor.getPath())
                  # Join adds a platform independent directory separator
                  fullname = join(curDirectory, filename)
        
                  subFolderToUse = ""
                  if atom.config.get 'markdown-local-attachments.use_subfolder'
                    # 根据设置获取子目录文件名
                    subFolderToUse = atom.config.get 'markdown-local-attachments.subfolder'
                    if subFolderToUse != ""
                      assetsDirectory = join(curDirectory, subFolderToUse)
                      # 如果子目录不存在则创建之
                      if !fs.existsSync assetsDirectory
                        fs.mkdirSync assetsDirectory
                      # 文件完整路径名
                      fullname = join(assetsDirectory, filename)

                  # 写图片到文件系统
                  fs.writeFileSync fullname, img.toPNG()

                  # 插入图片代码
                  text = ""
                  # 如果上一行不为空，则添加一个空行分割开来
                  if !cursor.getBuffer().isRowBlank(parseInt(position.row - 1))
                      text += "\r\n"
                      position.row = parseInt(position.row + 1)
                  # markdown图片显示代码生成
                  text += '![' + basename(filenameRaw, extname(filenameRaw)) + ']('
                  text += join(subFolderToUse, filename) + ') '
                  # 如果下一行不为空，则添加一个空行分割开来
                  if !cursor.getBuffer().isRowBlank(parseInt(position.row + 1))
                      text += "\r\n"
                      position.row = parseInt(position.row + 1)

          # 将反斜杠改成斜杠，这样在github和gitbook上都可以正常显示
          text = text.replace(/\\/g, "/");

          # 写代码到光标行
          cursor.insertText text
          position.column += text.length
          cursor.setCursorBufferPosition position

          if atom.config.get 'markdown-local-attachments.infoalertenable'
            if atom.config.get 'markdown-local-attachments.infoalertenable'
              atom.notifications.addSuccess(message = 'File attached', {detail:'Attachment path:' + fullname})

        # 捕获错误异常
        catch error
            if atom.config.get 'markdown-local-attachments.infoalertenable'
              atom.notifications.addError(message = 'Attachment failed', {detail:'Reason:' + error})

    deleteFile : ->
        try
          if !cursor = atom.workspace.getActiveTextEditor() then return

          # 检测当前文件是否为md文件，否则执行原有快捷键方式
          fileFormat = ""
          if !grammar = cursor.getGrammar() then return
          if cursor.getPath() and
             cursor.getPath().substr(-3) == '.md' or
                  cursor.getPath().substr(-9) == '.markdown' and
                    grammar.scopeName != 'source.gfm'
                      fileFormat = "md"
          else
              # 当前不在markdown文件中,执行原有操作
              cursor.deleteToBeginningOfLine()
              return

          # 选中图片代码区域，按快捷键ctrl-delete
          currRow = cursor.getCursorBufferPosition().row
          selectedToDelImg = cursor.lineTextForBufferRow(currRow)
          # 检测当前行是否为md链接
          markdownImageLinkPattern = ///!?\[[^\[\]]*\]\(([^()]+)\)///
          markdownImageLinkMatch = selectedToDelImg.match(markdownImageLinkPattern)
          if !markdownImageLinkMatch
              # 当前在markdown文件中，但是光标所在行不是md链接
              cursor.deleteToBeginningOfLine()
              return
          cursor.setSelectedBufferRange([[currRow,markdownImageLinkMatch.index],[currRow,markdownImageLinkMatch.index+markdownImageLinkMatch[0].length]])

          # 提取文件名
          filename = markdownImageLinkMatch[1]
          curDirectory = dirname(cursor.getPath())
          fullname = join(curDirectory, filename)

          # 检验文件存在与否
          if !fs.existsSync fullname
            if atom.config.get 'markdown-local-attachments.infoalertenable'
              atom.notifications.addError(message = 'Deletion failed', {detail:'File does't exist:' + fullname })
            return

          # 删除文件，删除链接内容
          fs.unlink fullname, (error) ->
              if error
                  if atom.config.get 'markdown-local-attachments.infoalertenable'
                      atom.notifications.addError(message = 'Deletion failed', {detail:'Reason:' + error})
                  return
              else
                  if atom.config.get 'markdown-local-attachments.infoalertenable'
                      atom.notifications.addSuccess(message = 'Deletion done', {detail:'[' + fullname + '] deleted'})
                  cursor.delete()

        # 捕获错误异常
        catch error
            if atom.config.get 'markdown-local-attachments.infoalertenable'
                atom.notifications.addError(message = 'Deletion failed', {detail:'Reason:' + error})

# 光标所在处插入text，光标移动到文本末尾
paste_text = (cursor, text) ->
    cursor.insertText text
    position = cursor.getCursorBufferPosition()
    #position.row = position.row - 1 就在光标所在行操作，无需上一行
    position.column = position.column + text.length + 1
    cursor.setCursorBufferPosition position


# 时间格式化
Date.prototype.format = ->
    # 保证两位数字显示，小于10前加'0'，大于100除10取整
    shift2digits = (val) ->
        if val < 10
            return "0#{val}"
        else if val > 99
            return parseInt(val/10)
        return val

    year = @getFullYear()
    month = shift2digits @getMonth()+1
    day = shift2digits @getDate()
    hour = shift2digits @getHours()
    minute = shift2digits @getMinutes()
    second = shift2digits @getSeconds()
    ms = shift2digits @getMilliseconds()

    return "#{year}#{month}#{day}_#{hour}#{minute}#{second}_#{ms}"
