# do not remove the { } from the top and bottom of this page!!!
#Simple_Chinese language module by Li DaoFeng <lidaof@cau.edu.cn>
#Modified from Tradition_Chinese version by Jack Chen <chenn@cshl.edu>
#Updated by Lam Man Ting Melody <paladinoflab@yahoo.com.hk> and Hu Zhiliang <zhilianghu@gmail.com>
#translation updated 2009.03.29
{

 CHARSET =>   'GB2312',

   #----------
   # MAIN PAGE
   #----------

   PAGE_TITLE => '基因组浏览器',

   SEARCH_INSTRUCTIONS => <<END,
可以使用序列名，基因名，遗传位点 %s 或其它标记进行搜索。允许使用通配符。
END

   NAVIGATION_INSTRUCTIONS => <<END,
 点击标尺使位点居中。使用卷动/缩放按钮改变放大倍数和位置。
END

   EDIT_INSTRUCTIONS => <<END,
在此编辑你上传的注释数据。
你可以利用制表符(tabs) 或 空格键(spaces) 来分界,
但对于数据已有的空白区域，则必须用单引号或双引号包括它们。
END

   SHOWING_FROM_TO => '显示 %s ，来自 %s，从 %s 到 %s',

   INSTRUCTIONS      => '介绍',

   HIDE              => '隐藏',

   SHOW              => '显示',

   SHOW_INSTRUCTIONS => '显示介绍',

   HIDE_INSTRUCTIONS => '隐藏介绍',

   SHOW_HEADER       => '显示标题',

   HIDE_HEADER       => '隐藏标题',

   LANDMARK => '域标',

   BOOKMARK => '添加到书签',

   IMAGE_LINK => '图像链接',

   PDF_LINK=> '下载PDF',

   SVG_LINK   => '高质量SVG图像',

   SVG_DESCRIPTION => <<END,
<p>
点击下面的链接将产生SVG格式的图像。SVG格式比jpg或png格式有更多优点。
</p>
<ul>
<li>不影响图像质量的情况下改变图像大小
<li>可以用普通图像软件进行编辑
<li>如果有需要可以转换成EPS格式供发表之用。
</ul>
<p>
要显示SVG图像, 需要浏览器支持SVG, 例如可以使用Adobe SVG 浏览器插件, 或者 Adobe Illustrator的SVG的查看和编辑软件。
</p>
<p>
Adobe的 SVG 浏览器插件: <a
href="http://www.adobe.com/support/downloads/product.jsp?product=46&platform=Macintosh">Macintosh</a>
| <a
href="http://www.adobe.com/support/downloads/product.jsp?product=46&platform=Windows">Windows</a>
<br />
Linux用户可以尝试使用 <a href="http://xml.apache.org/batik/">Batik SVG 查看器</a>.
</p>
<p>
<a href="%s" target="_blank">在新浏览器窗口中查看SVG图像</a></p>
<p>
按control-click (Macintosh) 或
鼠标右键 (Windows) 后选择适当选项可以将图像保存到计算机磁盘上。
</p>   
END

   IMAGE_DESCRIPTION => <<END,
<p>
生成内嵌于网页的图像, 剪切并粘贴图像的网址到HTML页面:
</p>
<pre>
&lt;IMAGE src="%s" /&gt;
</pre>
<p>
图像看起来应该是这样:
</p>
<p>
<img src="%s" />
</p>

<p>
如果选择显示概观 (染色体 或 contig), 请尽量缩小查看区域。
</p>
END

   TIMEOUT  => <<'END',
请求超时。您选择显示的区域可能太大而不能显示。
尝试关掉一些数据通道 或 选择稍小的区域.  如果仍未能奏效，请按红色的 "重置" 按钮。
END

   GO       => '执行',

   FIND     => '寻找',

   SEARCH   => '查询',

   DUMP     => '倾印',

   HIGHLIGHT   => '衬色',

   ANNOTATE     => '注释',

   SCROLL   => '移动/缩放',

   RESET    => '重置',

   FLIP     => '颠倒',

   DOWNLOAD_FILE    => '下载文件',

   DOWNLOAD_DATA    => '下载数据',

   DOWNLOAD         => '下载',

   DISPLAY_SETTINGS => '显示设置',

   TRACKS   => '数据通道',

   EXTERNAL_TRACKS => '<i>外部数据通道（斜体）</i>',

   OVERVIEW_TRACKS => '<sup>*</sup>数据通道概观',

   REGION_TRACKS => '<sup>**</sup>数据通道区域',

   EXAMPLES => '范例',

   REGION_SIZE => '区域大小 (bp)',

   HELP     => '帮助',

   HELP_FORMAT => '帮助文件格式',

   CANCEL   => '取消',

   ABOUT    => '关于...',

   REDISPLAY   => '重新显示',

   CONFIGURE   => '配置...',

   CONFIGURE_TRACKS   => '配置数据通道...',

   EDIT       => '编辑文件...',

   DELETE     => '删除文件',

   EDIT_TITLE => '进入/编辑 注释数据',

   IMAGE_WIDTH => '图像宽度',

   BETWEEN     => '之间',

   BENEATH     => '下面',

   LEFT        => '左面',

   RIGHT       => '右面',

   TRACK_NAMES => '数据通道名称表',

   ALPHABETIC  => '字母',

   VARYING     => '变化',

   SHOW_GRID    => '显示网格',

   SET_OPTIONS => '设定数据通道选项...',

   CLEAR_HIGHLIGHTING => '清除衬色',

   UPDATE      => '更新图像',

   DUMPS       => '保存，查询及其它选择',

   DATA_SOURCE => '数据来源',

   UPLOAD_TRACKS=>'上传您自己的数据通道',

   UPLOAD_TITLE=> '上传您自己的注释',

   UPLOAD_FILE => '上传一个文件',

   KEY_POSITION => '注释位置',

   BROWSE      => '浏览...',

   UPLOAD      => '上传',

   NEW         => '新增...',

   REMOTE_TITLE => '添加远程注释',

   REMOTE_URL   => '键入远程注释网址',

   UPDATE_URLS  => '更新网址',

   PRESETS      => '--选择当前网址--',

   FEATURES_TO_HIGHLIGHT => '衬色特性 (特性1 特性2...)',

   REGIONS_TO_HIGHLIGHT => '衬色区域 (区域1:起始..结束 区域2:起始..结束)',

   FEATURES_TO_HIGHLIGHT_HINT => '提示: 用特征@color 选择颜色, 如 \'NUT21@lightblue\'',

   REGIONS_TO_HIGHLIGHT_HINT  => '提示: 用特征@color 选择颜色, 如 \'Chr1:10000..20000@lightblue\'',

   NO_TRACKS    => '*空白*',

   FILE_INFO    => '最后修改于 %s.  注释标志: %s',

   FOOTER_1     => <<END,
注意: 此页面使用cookies来保存和恢复用户偏好信息。
用户信息不会泄露。
END

   FOOTER_2    => '通用基因组浏览器版本 %s',

   #----------------------
   # MULTIPLE MATCHES PAGE
   #----------------------

   HIT_COUNT      => '下列 %d 区域符合您的要求',

   POSSIBLE_TRUNCATION  => '搜索结果：大约有 %d 相符结果; 列出的结果可能不完整	。',

   MATCHES_ON_REF => '相符结果; %s',

   SEQUENCE        => '序列',

   SCORE           => '得分=%s',

   NOT_APPLICABLE => '不适用',

   BP             => 'bp',

   #--------------
   # SETTINGS PAGE
   #--------------

   SETTINGS => '%s 的设置',

   UNDO     => '取消更改',

   REVERT   => '恢复到初始值',

   REFRESH  => '刷新',

   CANCEL_RETURN   => '取消更改并返回...',

   ACCEPT_RETURN   => '接受更改并返回...',

   OPTIONS_TITLE => '数据通道选项',

   SETTINGS_INSTRUCTIONS => <<END,
<i>显示</i> 复选框可以打开或关闭数据通道。
<i>简洁</i> 选项强制压缩数据通道，所以有些注释会重叠。<i>扩展</i> 和 <i>通过链接扩展</i>
选用快速或慢速规划算法来控制界面相容性。<i>扩展</i> 和 <i>标记</i> 以及 <i>通过链接的扩展和标记 </i> 选项强制注释被标记。
如果选择了<i>自动</i> 选项, 空间允许的条件下界面相容控制和标记选项将会设置为自动。
要改变数据通道的顺序可以使用 <i>更改数据通道顺序</i> 弹出菜单 并为数据通道分配一个注释. 要限制注释的数目, 请更改
 <i>限制</i> 菜单的值。
END

   TRACK  => '数据通道',

   TRACK_TYPE => '数据通道类型',

   SHOW => '显示',

   FORMAT => '格式',

   LIMIT  => '限制',

   ADJUST_ORDER => '顺序调整',

   CHANGE_ORDER => '更改数据通道顺序',

   AUTO => '自动',

   COMPACT => '简洁',#紧缩 / 压缩

   EXPAND => '扩展',

   EXPAND_LABEL => '扩展并标记',

   HYPEREXPAND => '通过链接扩展',

   HYPEREXPAND_LABEL =>'通过链接扩展并标记',

   NO_LIMIT    => '无限制',

   OVERVIEW    => '概观',

   EXTERNAL    => '外部的',

   ANALYSIS    => '分析',

   GENERAL     => '一般',

   DETAILS     => '细节',

   REGION      => '区域',

   ALL_ON      => '全开',

   ALL_OFF     => '全关',

   #--------------
   # HELP PAGES
   #--------------

   CLOSE_WINDOW => '关闭窗口',

   TRACK_DESCRIPTIONS => '数据通道的描述和引用',

   BUILT_IN           => '这个服务器内在的数据通道',

   EXTERNAL           => '外部注释数据通道',

   ACTIVATE           => '请激活此数据通道并查看相关信息',

   NO_EXTERNAL        => '没有载入外部特征',

   NO_CITATION        => '没有额外的相关信息.',

   #--------------
   # PLUGIN PAGES
   #--------------

 ABOUT_PLUGIN  => '关于 %s',

 BACK_TO_BROWSER => '返回到浏览器',

 PLUGIN_SEARCH   => '%s (通过 %s 搜索)',

 #PLUGIN_SEARCH  => 'search via the %s plugin'
 #PLUGIN_SEARCH_1   => '%s (通过 %s 搜索)',
 #PLUGIN_SEARCH_2   => '&lt;%s 查询&gt;',

 CONFIGURE_PLUGIN   => '配置',

 BORING_PLUGIN => '此插件无需额外设置',

   #--------------
   # ERROR MESSAGES
   #--------------

 NOT_FOUND => '无法识别名为 <i>%s</i> 的标志。 请查看帮助页面。',

 TOO_BIG   => '查看范围限制在 %s 碱基的细节。  在概览中点击选择 %s 宽的区域.',

 PURGED    => "找不到文件 %s 。  可能已被删除?",

 NO_LWP    => "此服务器不支持获取外部网址",

 FETCH_FAILED  => "不能获取 %s: %s.",

 TOO_MANY_LANDMARKS => '%d 标志，标志太多未能全部显示。',

 SMALL_INTERVAL    => '将区域缩小到 %s bp',

 NO_SOURCES        => '没有配置可读取的数据源.  或者您没有权限查看它们',

# Missed Terms

 ADD_YOUR_OWN_TRACKS => '添加您自己的通道数据',

 INVALID_SOURCE    => '来源 %s 不合理.',

 BACKGROUND_COLOR  => '填充颜色',

 FG_COLOR          => '线条颜色',

 HEIGHT           => '高度',

 PACKING          => '包装',

 GLYPH            => '样式',

 LINEWIDTH        => '线条宽度',

 DEFAULT          => '(启始状态)',

 DYNAMIC_VALUE    => '动态计算值',

 CHANGE           => '更改',

 DRAGGABLE_TRACKS  => '可拖曳数据通道',

 CACHE_TRACKS      => '数据通道缓存',

 CHANGE_DEFAULT  => '更改初始值',

 SHOW_TOOLTIPS     => '显示工具提示',

 OPTIONS_RESET     => '所有页面设置恢复到初始值',

 OPTIONS_UPDATED   => '新的站点配置生效; 所有页面设置已恢复到初始值',
 
SEND_TO_GALAXY    => '传送此区域至Galaxy',
#Galaxy http://main.g2.bx.psu.edu/

 NO_DAS            => '安装错误: 必须先安装Bio::Das 模组才能执行DAS 网址。请通知本站管理员。',

 SHOW_OR_HIDE_TRACK => '<b>显示或隐藏此数据通道</b>',

 CONFIGURE_THIS_TRACK   => '<b>按此更改数据通道设定。</b>',

 SHARE_THIS_TRACK   => '<b>分享此数据通道</b>',

 SHARE_ALL          => '分享这些数据通道',

 SHARE              => '分享 %s',

 SHARE_INSTRUCTIONS_ONE_TRACK => <<END,
如欲分享此数据通道给其他通用基因组浏览器，先复制以下网址，然後前往另外的基因组浏览器并於页底之"输入远程注释"栏位贴上此网址。请注意：若此数据通道源自上载档案,分享以下网址给其他使用者可能让其他使用者观看上载档案之<b>全部</b>内容。
END

 SHARE_INSTRUCTIONS_ALL_TRACKS => <<END,
如欲分享所有已选之数据通道给其他通用基因组浏览器，先复制以下网址，然後前往另外的基因组浏览器并於页底之"输入远程注释"栏位贴上此网址。请注意：若任何已选之数据通道源自上载档案,分享以下网址给其他使用者可能让其他使用者观看上载档案之<b>全部</b>内容。
END

 SHARE_DAS_INSTRUCTIONS_ONE_TRACK => <<END,
如欲透过<a href="http://www.biodas.org" target="_new">分布式注释系统
(Distributed Annotation System, DAS)</a> 分享此数据通道给其他通用基因组浏览器，先复制以下网址，然後前往另外的基因组浏览器并於输入为新的DAS来源。<i>定量数据通道 ("wiggle"档案)及上载档案不能以DAS分享。</i>
END

 SHARE_DAS_INSTRUCTIONS_ALL_TRACKS => <<END,
如欲透过<a href="http://www.biodas.org" target="_new">分布式注释系统
(Distributed Annotation System, DAS)</a> 分享所有已选之数据通道给其他通用基因组浏览器，先复制以下网址，然後前往另外的基因组浏览器并於输入为新的DAS来源。<i>定量数据通道 ("wiggle"档案)及上载档案不能以DAS分享。</i>
END

};

