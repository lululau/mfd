require 'mfd/asset'
require 'optparse'

module Mfd
  class Cli

    def initialize
      @predicates = ['(true)']
      @print_command = false
      @ascii_null = false
      @live = false
      @count = false

      @opt = OptionParser.new
      declare_options!
    end

    def parse_options!(args)
      if args.empty?
        puts @opt
        exit
      end

      @opt.parse!(args)

      if args.size == 1
        dir = args.first
        dir = File.expand_path dir unless dir =~ /^\//
        scope = "-onlyin '#{escape dir}'"
      else
        scope = ''
      end

      query_string = @predicates.join(' && ')

      cmd = "mdfind #{scope} \
  #{@ascii_null ? '-0' : ''} \
  #{@live ? '-live' : ''} \
  #{@count ? '-count' : ''} \
'#{query_string}'"

      puts cmd if @print_command

      system cmd
    end

    def declare_options!
      @opt.banner = <<-BANNER
      mdfind4 - a better mdfind built upon mdfind3

      Spotlight 是 OS X 上非常好用的一个桌面搜索工具，mdfind 是Spotlight 的 CLI frontend，
      虽然 mdfind 的功能足够强大，但是界面非常不友好，例如，要搜索电脑中2013年的文件大小大于 1MB
      的jpg图像文件，需要一个非常复杂的命令。mdfind4 对mdfind进行封装，提供比较易用的界面

      mdfind3: https://gist.github.com/4086771

      usage: mdfind4 [options] [search dir]

        通过指定若干选项来搜索文件系统中被 Spotlight 索引的文件，每个选项之间是逻辑与的关系. 默认将
        搜索文件系统中所有的被索引文件，可以通过最后一个参数来约束其只在某个目录中进行搜索.

        % mdfind4 --content-type com.omnigroup.omnigraffle.graffle --from 2011/11/1 -t '2013-01-01 14:30:24'
        % mdfind4 --query '关键字' --content-type 'com.adobe.pdf'
        % mdfind4 -e mp3 -b10M

      options:

        以下选项均支持以一个 "@" 符号开头, 后跟一个文件名，表示此选项的值将从给定的文件中提取:

          • -f, --from
          • -t, --to
          • -F, --from-create
          • -T, --to-create
          • -c, --content-type
          • -k, --kind
          • -b, --biggerthan
          • -s, --smallerthan

      BANNER

      @opt.on('-f from', '--from from', "e.g. --from 2010/1/1
        #{' ' * 35}搜索\"文件最后修改时间\"等于或晚于指定时间的文件，时间格式为\"YYYY-mm-dd HH:MM:SS\"
        #{' ' * 35}其中可以使用任意非数字字符作为分隔符，也可以只指定日期部分。
        #{' ' * 35}另外, -f 选项还支持指定一个数字后跟一个字母的形式来指定时间,
        #{' ' * 35}支持的字符包括: S, M, H, d, m, Y，分别表示: 秒, 分, 时,
        #{' ' * 35}天, 月, 年, 其中一个月等于 30 天, 一年等于 365 天.
        #{' ' * 35}例如, 搜索最近 10 天的文件: -f 10d
        ") do |from|
        @predicates << 'kMDItemFSContentChangeDate >= %i' % (from.start_with?('@') ?
          prop_value_from_file(from, 'kMDItemFSContentChangeDate') : calculate_time(from))
      end

      @opt.on('-t to', '--to to', "搜索\"文件最后修改时间\"等于或早于指定时间的文件, 格式同\"-f\"选项
        ") do |to|
        @predicates << 'kMDItemFSContentChangeDate <= %i' % (to.start_with?('@') ?
          prop_value_from_file(to, 'kMDItemFSContentChangeDate') : calculate_time(to))
      end

      @opt.on('-F from', '--from-create from', "搜索\"文件创建时间\"等于或晚于指定时间的文件, 格式同\"-f\"选项
        ") do |from|
        @predicates << 'kMDItemFSCreationDate >= %i' % (from.start_with?('@') ?
          prop_value_from_file(from, 'kMDItemFSCreationDate') : calculate_time(from))
      end

      @opt.on('-T to', '--to-create to', "搜索\"文件创建时间\"等于或早于指定时间的文件, 格式同\"-f\"选项
        ") do |to|
        @predicates << 'kMDItemFSCreationDate <= %i' % (to.start_with?('@') ?
          prop_value_from_file(to, 'kMDItemFSCreationDate') : calculate_time(to))
      end

      @opt.on('-q query', '--query query', 'e.g. --query "关键字"
        ') do |query|
        @predicates << 'kMDItemTextContent == "%s"cdw' % escape(query)
      end

      @opt.on('-c contenttype', '--content-type contenttype', "e.g. --contenttype com.omnigroup.omnigraffle.graffle
        #{' ' * 35}搜索 \"kMDItemContentType\" 属性等于指定值的文件，可以不
        #{' ' * 35}指定完整的 Content Type，例如 Ruby 脚本的 Content Type
        #{' ' * 35}为 \"public.ruby-script\"，但是可以使用下面的命令所有所有
        #{' ' * 35}Ruby 脚本文件：mdfind4 -c ruby
        ") do |contenttype|
        @predicates << 'kMDItemContentType == "%s"cdw' % (contenttype.start_with?('@') ?
          prop_value_from_file(contenttype, 'kMDItemContentType') : escape(contenttype))
      end

      @opt.on('-e file-ext-name', '--type file-ext-name', ".e.g  -e 'mp3'
        #{' ' * 35}ContentType 字符串不便记忆，为了方便使用，本程序将常用的
        #{' ' * 35}文件类型的后缀名和 kMDItemKind 字符串建立关联，可以使用本选项
        #{' ' * 35}来指定要搜索的文件的后缀名, 可以使用\"-l\"选项查看所有支持的后
        #{' ' * 35}缀名以及关联
        ") do |type|
        unless Mfd::Asset::KIND_MAP[type]
          STDERR.puts "Not supported file ext name: #{type}, use `mfd -l' to see all supported file ext names`"
          exit(1)
        end
        @predicates << 'kMDItemKind == "*%s*"cdw' % escape(Mfd::Asset::KIND_MAP[type])
      end

      @opt.on('-l', '--list-types', "kMDItemKind 字符串不便记忆，为了方便使用，本程序将常用的
        #{' ' * 35}文件类型的后缀名和 kMDItemKind 字符串建立关联，使用本选项
        #{' ' * 35}看所有支持的后缀名以及关联
        ") do
        puts
        Mfd::Asset::KIND_MAP.keys.sort.each do |e|
          printf "\t%-10s : %s\n", e, Mfd::Asset::KIND_MAP[e]
        end
        puts
        exit
      end

      @opt.on('-k kind', '--kind kind', "e.g. --kind \"HTML Document\"
        #{' ' * 35}\"-k\"选项是另外一个用来指定文件类型的选项，它使用
        #{' ' * 35}\"kMDItemKind\"属性来搜索文件. 例如, 搜索邮件: \"-k 邮件信息\"
        #{' ' * 35}搜索 Safari 历史记录: \"-k 'Safari 历史记录项目'\"
        ") do |kind|
        @predicates << 'kMDItemKind == "*%s*"cdw' % (kind.start_with?('@') ?
          prop_value_from_file(kind, 'kMDItemKind') : escape(kind))
      end

      @opt.on('-b size', '--bigger-than size', "e.g. --bigger-than 100000
        #{' ' * 35}搜索文件大小大于或等于给定值的文件，可以使用 t, g, m, k 等单位,
        #{' ' * 35}例如, 搜索大于或等于 1MB 字节的文件：\"-b 1m\"
        ") do |size|
        @predicates << 'kMDItemFSSize >= %s' % (size.start_with?('@') ?
          prop_value_from_file(size, 'kMDItemFSSize') : calculate_size(size).to_s)
      end

      @opt.on('-s sizes', '--smaller-than size', "e.g. --smaller-than 100000
        #{' ' * 35}搜索文件大小小于或等于给定值的文件，可以使用 t, g, m, k 等单位,
        #{' ' * 35}例如, 搜索小于或等于 1GB 字节的文件：\"-b 1G\"
        ") do |size|
        @predicates << 'kMDItemFSSize <= %s' % (size.start_with?('@') ?
          prop_value_from_file(size, 'kMDItemFSSize') : calculate_size(size).to_s)
      end

      @opt.on('', '--prop-eq arg_value', "e.g. --prop-eq FSSize@diary.txt
        #{' ' * 35}不同类型的文件各自都有多种多样的属性，本程序支持的属性比较有限, 若需要
        #{' ' * 35}按照其他属性比较，则使用本选项以及下面三个以 \"--prop\"
        #{' ' * 35}打头的选项。可以通过 OS X 自带的 \"mdls\" 命令来查看文件的各种属性,
        #{' ' * 35}属性名称一般以 \"kMDItem\" 打头，使用这四个选项时可以只指定 \"kMDItem\"
        #{' ' * 35}后面的部分, 本选项的值的格式为 \"property@filename\", 例如,
        #{' ' * 35}搜索文件大小等于 a.txt 的所有文件：--prop-eq FSSize@./a.txt
        ") do |arg_value|
        prop_key, filename = arg_value.split('@')
        prop_key = 'kMDItem' + prop_key unless prop_key.start_with?('kMDItem')
        filename = File.expand_path filename
        @predicates << "#{prop_key} == %s" % prop_value_from_file(filename, prop_key)
      end

      @opt.on('', '--prop-ne arg_value', 'e.g. --prop-ne FSSize@diary.txt
        ') do |arg_value|
        prop_key, filename = arg_value.split('@')
        prop_key = 'kMDItem' + prop_key unless prop_key.start_with?('kMDItem')
        filename = File.expand_path filename
        @predicates << "#{prop_key} != %s" % prop_value_from_file(filename, prop_key)
      end

      @opt.on('', '--prop-le arg_value', 'e.g. --prop-le FSSize@diary.txt
        ') do |arg_value|
        prop_key, filename = arg_value.split('@')
        prop_key = 'kMDItem' + prop_key unless prop_key.start_with?('kMDItem')
        filename = File.expand_path filename
        @predicates << "#{prop_key} <= %s" % prop_value_from_file(filename, prop_key)
      end

      @opt.on('', '--prop-ge arg_value', 'e.g. --prop-ge FSSize@diary.txt
        ') do |arg_value|
        prop_key, filename = arg_value.split('@')
        prop_key = 'kMDItem' + prop_key unless prop_key.start_with?('kMDItem')
        filename = File.expand_path filename
        @predicates << "#{prop_key} >= %s" % prop_value_from_file(filename, prop_key)
      end

      @opt.on('-d url', '--downloadfrom url', '搜索从URL下载的文件') do |url|
        @predicates << 'kMDItemWhereFroms == "%s"' % "*#{escape(url)}*" # 曖昧指定
      end

      @opt.on('-n name', '--name name', '按文件名称搜索, 自动支持模糊匹配, 无需指定通配符') do |name|
        @predicates << 'kMDItemFSName == "%s"cdw' % escape(name)
      end

      @opt.on('-0', '--null', "Prints an ASCII NUL character after each result path.
        #{' ' * 35}This is useful when used in conjunction with
        #{' ' * 35}xargs -0.") do
        @ascii_null = true
      end

      @opt.on('', '--live', "Causes the mdfind command to provide live-updates to the
        #{' ' * 35}number of files matching the query. When an
        #{' ' * 35}update causes the query results to change the
        #{' ' * 35} number of matches is updated.  The find can
        #{' ' * 35}be cancelled by typing ctrl-C.
        ") do
        @live = true
      end

      @opt.on('', '--count', "Causes the mdfind command to output the total number of
        #{' ' * 35}matches, instead of the path to the matching
        #{' ' * 35}items.
        ") do
        @count = true
      end

      @opt.on('', '--debug', "mdfind4 通过调用 OS X 系统自带的 mdfind 命令来完成文件搜索，指定
        #{' ' * 35}本选项之后, 可以看到 mdfind4 实际调用的命令的参数
        ") do
        @print_command = true
      end
    end

    def escape(str)
      str.gsub(/"/, '\\"')
    end

    def calculate_size(size_str)
      case size_str
      when /(\d+)t$/i
        Regexp.last_match(1).to_i * 1024**4
      when /(\d+)g$/i
        Regexp.last_match(1).to_i * 1024**3
      when /(\d+)m$/i
        Regexp.last_match(1).to_i * 1024**2
      when /(\d+)k$/i
        Regexp.last_match(1).to_i * 1024
      else
        Regexp.last_match(1).to_i
      end
    end

    def calculate_time(time_str)
      datum = Time.gm 2001

      case time_str
      when /^(\d+)S$/
        NOW - datum - Regexp.last_match(1).to_i
      when /^(\d+)M$/
        NOW - datum - Regexp.last_match(1).to_i * 60
      when /^(\d+)H$/
        NOW - datum - Regexp.last_match(1).to_i * 3600
      when /^(\d+)d$/
        NOW - datum - Regexp.last_match(1).to_i * 86_400
      when /^(\d+)m$/
        NOW - datum - Regexp.last_match(1).to_i * 2_592_000
      when /^(\d+)Y$/
        NOW - datum - Regexp.last_match(1).to_i * 946_080_000
      else
        ymd = time_str.split(/\D+/)
        Time.local(*ymd) - datum
      end
    end

    def prop_value_from_file(filename, key)
      filename = File.expand_path filename.sub(/^@/) { '' }
      IO.popen("mdls '#{filename}'", 'r') do |io|
        while line = io.gets
          next unless line =~ /#{key}\s*=\s*(.+)/
          value_str = Regexp.last_match(1)
          case value_str
          when /^"([^"]*)"$/
            return Regexp.last_match(1)
          when /^(\d+)$/
            return Regexp.last_match(1)
          when /^(.*) \+0000$/
            ymd = Regexp.last_match(1).split(/\D+/)
            return Time.gm(*ymd) - Time.gm(2001)
          else
            next
          end
        end
        return nil
      end
    end
  end
end
