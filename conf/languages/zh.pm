# do not remove the { } from the top and bottom of this page!!!
#Simple_Chinese language module by Li DaoFeng <lidaof@gmail.com>
#Modified from Tradition_Chinese version by Jack Chen <chenn@cshl.edu>
#Updated by Lam Man Ting Melody <paladinoflab@yahoo.com.hk> and Hu Zhiliang <zhilianghu@gmail.com>
#translation updated 2009.03.29
{

 CHARSET =>   'Big5',

   #----------
   # MAIN PAGE
   #----------

   PAGE_TITLE => '基因組瀏覽器',

   SEARCH_INSTRUCTIONS => <<END,
<b>搜索:</b> 可以使用序列名，基因名，遺傳位點 %s 或其它標記進行搜索。允許使用通配符*。
END

   NAVIGATION_INSTRUCTIONS => <<END,
 <br><b>導覽:</b> 點擊標尺使位點居中。使用卷動/縮放按鈕改變放大倍數和位置。
END

   EDIT_INSTRUCTIONS => <<END,
在此編輯你上傳的注釋數據。
你可以利用制表符(tabs) 或 空格鍵(spaces) 來分界,
但對於數據已有的空白區域，則必須用單引號或雙引號包括它們。
END

   SHOWING_FROM_TO => '顯示 %s ，來自 %s，從 %s 到 %s',

   INSTRUCTIONS      => '介紹',

   HIDE              => '隱藏',

   SHOW              => '顯示',

   SHOW_INSTRUCTIONS => '顯示介紹',

   HIDE_INSTRUCTIONS => '隱藏介紹',

   SHOW_HEADER       => '顯示標題',

   HIDE_HEADER       => '隱藏標題',

   LANDMARK => '區域標誌',

   BOOKMARK => '添加到書簽',

   IMAGE_LINK => '圖像鏈接',

   PDF_LINK=> '下載PDF',

   SVG_LINK   => '高質量SVG圖像',

   SVG_DESCRIPTION => <<END,
<p>
點擊下面的鏈接將產生SVG格式的圖像。SVG格式比jpg或png格式有更多優點。
</p>
<ul>
<li>不影響圖像質量的情況下改變圖像大小
<li>可以用普通圖像軟件進行編輯
<li>如果有需要可以轉換成EPS格式供發表之用。
</ul>
<p>
要顯示SVG圖像, 需要瀏覽器支持SVG, 例如可以使用Adobe SVG 瀏覽器插件, 或者 Adobe Illustrator的SVG的查看和編輯軟件。
</p>
<p>
Adobe的 SVG 瀏覽器插件: <a
href="http://www.adobe.com/support/downloads/product.jsp?product=46&platform=Macintosh">Macintosh</a>
| <a
href="http://www.adobe.com/support/downloads/product.jsp?product=46&platform=Windows">Windows</a>
<br />
Linux用戶可以嘗試使用 <a href="http://xml.apache.org/batik/">Batik SVG 查看器</a>.
</p>
<p>
<a href="%s" target="_blank">在新瀏覽器窗口中查看SVG圖像</a></p>
<p>
按control-click (Macintosh) 或
鼠標右鍵 (Windows) 後選擇適當選項可以將圖像保存到電腦磁盤。
</p>   
END

   IMAGE_DESCRIPTION => <<END,
<p>
生成內嵌於網頁的圖像, 剪切並粘貼圖像的網址到HTML頁面:
</p>
<pre>
&lt;IMAGE src="%s" /&gt;
</pre>
<p>
圖像看起來應該是這樣:
</p>
<p>
<img src="%s" />
</p>

<p>
如果選擇顯示概觀 (染色體 或 contig), 請盡量縮小查看區域。
</p>
END

   TIMEOUT  => <<'END',
請求超時。您選擇顯示的區域可能太大而不能顯示。
嘗試關掉一些數據通道 或 選擇稍小的區域.  如果仍未能奏效，請按紅色的 "重置" 按鈕。
END

   GO       => '執行',

   FIND     => '尋找',

   SEARCH   => '查詢',

   DUMP     => '傾印',

   HIGHLIGHT   => '強調',

   ANNOTATE     => '注釋',

   SCROLL   => '卷動/縮放',

   RESET    => '重置',

   FLIP     => '顛倒',

   DOWNLOAD_FILE    => '下載文件',

   DOWNLOAD_DATA    => '下載數據',

   DOWNLOAD         => '下載',

   DISPLAY_SETTINGS => '顯示設置',

   TRACKS   => '數據通道',

   EXTERNAL_TRACKS => '<i>外部數據通道（斜體）</i>',

   OVERVIEW_TRACKS => '<sup>*</sup>數據通道概觀',

   REGION_TRACKS => '<sup>**</sup>數據通道區域',

   EXAMPLES => '範例',

   REGION_SIZE => '區域大小 (bp)',

   HELP     => '幫助',

   HELP_FORMAT => '幫助文件格式',

   CANCEL   => '取消',

   ABOUT    => '關於...',

   REDISPLAY   => '重新顯示',

   CONFIGURE   => '配置...',

   CONFIGURE_TRACKS   => '配置數據通道...',

   EDIT       => '編輯文件...',

   DELETE     => '刪除文件',

   EDIT_TITLE => '進入/編輯 注釋數據',

   IMAGE_WIDTH => '圖像寬度',

   BETWEEN     => '之間',

   BENEATH     => '下面',

   LEFT        => '左面',

   RIGHT       => '右面',

   TRACK_NAMES => '數據通道名稱表',

   ALPHABETIC  => '字母',

   VARYING     => '變化',

   SHOW_GRID    => '顯示網格',

   SET_OPTIONS => '設定數據通道選項...',

   CLEAR_HIGHLIGHTING => '清除強調',

   UPDATE      => '更新圖像',

   DUMPS       => '保存，查詢及其它選擇',

   DATA_SOURCE => '數據來源',

   UPLOAD_TRACKS=>'上傳您自己的數據通道',

   UPLOAD_TITLE=> '上傳您自己的注釋',

   UPLOAD_FILE => '上傳一個文件',

   KEY_POSITION => '注釋位置',

   BROWSE      => '瀏覽...',

   UPLOAD      => '上傳',

   NEW         => '新增...',

   REMOTE_TITLE => '添加遠程注釋',

   REMOTE_URL   => '鍵入遠程注釋網址',

   UPDATE_URLS  => '更新網址',

   PRESETS      => '--選擇當前網址--',

   FEATURES_TO_HIGHLIGHT => '強調特性 (特性1 特性2...)',

   REGIONS_TO_HIGHLIGHT => '強調區域 (區域1:起始..結束 區域2:起始..結束)',

   FEATURES_TO_HIGHLIGHT_HINT => '提示: 用特徵@color 選擇顏色, 如 \'NUT21@lightblue\'',

   REGIONS_TO_HIGHLIGHT_HINT  => '提示: 用特徵@color 選擇顏色, 如 \'Chr1:10000..20000@lightblue\'',

   NO_TRACKS    => '*空白*',

   FILE_INFO    => '最後修改於 %s.  注釋標誌: %s',

   FOOTER_1     => <<END,
注意: 此頁面使用cookies來保存和恢復用戶偏好信息。
用戶信息不會泄露。
END

   FOOTER_2    => '通用基因組瀏覽器版本 %s',

   #----------------------
   # MULTIPLE MATCHES PAGE
   #----------------------

   HIT_COUNT      => '下列 %d 區域符合您的要求',

   POSSIBLE_TRUNCATION  => '搜索結果：大約有 %d 相符結果：列出的結果可能不完整。',

   MATCHES_ON_REF => '相符結果： %s',

   SEQUENCE        => '序列',

   SCORE           => '得分=%s',

   NOT_APPLICABLE => '不適用',

   BP             => 'bp',

   #--------------
   # SETTINGS PAGE
   #--------------

   SETTINGS => '%s 的設置',

   UNDO     => '取消更改',

   REVERT   => '恢復到預設值',

   REFRESH  => '刷新',

   CANCEL_RETURN   => '取消更改並返回...',

   ACCEPT_RETURN   => '接受更改並返回...',

   OPTIONS_TITLE => '數據通道選項',

   SETTINGS_INSTRUCTIONS => <<END,
<i>顯示</i> 復選框可以打開或關閉數據通道。
<i>簡潔</i> 選項強制壓縮數據通道，所以有些注釋會重疊。<i>擴展</i> 和 <i>通過鏈接擴展</i>
選用快速或慢速規劃算法來控制界面相容性。<i>擴展</i> 和 <i>標記</i> 以及 <i>通過鏈接的擴展和標記 </i> 選項強制注釋被標記。
如果選擇了<i>自動</i> 選項, 空間允許的條件下界面相容控制和標記選項將會設置為自動。
要改變數據通道的順序可以使用 <i>更改數據通道順序</i> 彈出菜單 並為數據通道分配一個注釋. 要限制注釋的數目, 請更改
 <i>限制</i> 菜單的值。
END

   TRACK  => '數據通道',

   TRACK_TYPE => '數據通道類型',
   
   SHOW => '顯示',

   FORMAT => '格式',

   LIMIT  => '限制',

   ADJUST_ORDER => '順序調整',

   CHANGE_ORDER => '更改數據通道順序',

   AUTO => '自動',

   COMPACT => '簡潔', #緊縮 / 壓縮',

   EXPAND => '擴展',

   EXPAND_LABEL => '擴展並標記',

   HYPEREXPAND => '通過鏈接擴展',

   HYPEREXPAND_LABEL =>'通過鏈接擴展並標記',

   NO_LIMIT    => '無限制',

   OVERVIEW    => '概覽',

   EXTERNAL    => '外部的',

   ANALYSIS    => '分析',

   GENERAL     => '一般',

   DETAILS     => '細節',

   REGION      => '區域',

   ALL_ON      => '全開',

   ALL_OFF     => '全關',

   #--------------
   # HELP PAGES
   #--------------
   
   OK => '確定',

   CLOSE_WINDOW => '關閉窗口',

   TRACK_DESCRIPTIONS => '數據通道的描述和引用',

   BUILT_IN           => '這個服務器內在的數據通道',

   EXTERNAL           => '外部注釋數據通道',

   ACTIVATE           => '請激活此數據通道並查看相關信息',

   NO_EXTERNAL        => '沒有載入外部特征',

   NO_CITATION        => '沒有額外的相關信息.',

   #--------------
   # PLUGIN PAGES
   #--------------

 ABOUT_PLUGIN  => '關於 %s',

 BACK_TO_BROWSER => '返回到瀏覽器',

 PLUGIN_SEARCH   => '%s (通過 %s 搜索)',

#PLUGIN_SEARCH   => 'search via the %s plugin',
#PLUGIN_SEARCH_1   => '%s (通過 %s 搜索)',
#PLUGIN_SEARCH_2   => '&lt;%s 查詢&gt;',

 CONFIGURE_PLUGIN   => '配置',

 BORING_PLUGIN => '此插件無需額外設置',

   #--------------
   # ERROR MESSAGES
   #--------------

 NOT_FOUND => '無法識別名為 <i>%s</i> 的標誌。 請查看幫助頁面。',

 TOO_BIG   => '查看範圍限制在 %s 堿基的細節。  在概覽中點擊選擇 %s 寬的區域.',

 PURGED    => "找不到文件 %s 。  可能已被刪除?",

 NO_LWP    => "此服務器不支持獲取外部網址",

 FETCH_FAILED  => "不能獲取 %s: %s.",

 TOO_MANY_LANDMARKS => '%d 標誌，標誌太多未能全部顯示。',

 SMALL_INTERVAL    => '將區域縮小到 %s bp',

 NO_SOURCES        => '沒有配置可讀取的數據源.  或者您沒有權限查看它們',

# Missed Terms

 ADD_YOUR_OWN_TRACKS => '添加您自己的數據通道',
 
 INVALID_SOURCE    => '來源 %s 不合理.',

 BACKGROUND_COLOR  => '填充顏色',

 FG_COLOR          => '線條顏色',

 HEIGHT           => '高度',

 PACKING          => '包裝',

 GLYPH            => '樣式',

 LINEWIDTH        => '線條寬度',

 DEFAULT          => '(預設)',

 DYNAMIC_VALUE    => '動態計算值',

 CHANGE           => '更改',

 DRAGGABLE_TRACKS  => '可拖曳數據通道',

 CACHE_TRACKS      => '緩存數據通道',

 CHANGE_DEFAULT  => '更改預設值',

 SHOW_TOOLTIPS     => '顯示工具提示',

 OPTIONS_RESET     => '所有頁面設置恢復到預設值',

 OPTIONS_UPDATED   => '新的站點配置生效; 所有頁面設置已恢復到預設值',

 SEND_TO_GALAXY    => '傳送此區域至Galaxy',
#Galaxy http://main.g2.bx.psu.edu/

 NO_DAS            => '安裝錯誤: 必須先安裝Bio::Das 模組才能執行DAS 網址。請通知本站管理員。',

 SHOW_OR_HIDE_TRACK => '<b>顯示或隱藏此數據通道</b>',

 CONFIGURE_THIS_TRACK   => '<b>按此更改數據通道設定。</b>',

 SHARE_THIS_TRACK   => '<b>分享此數據通道</b>',

 SHARE_ALL          => '分享這些數據通道',

 SHARE              => '分享 %s',

 SHARE_INSTRUCTIONS_ONE_TRACK => <<END,
如欲分享此數據通道給其他通用基因組瀏覽器，先複製以下網址，然後前往另外的基因組瀏覽器並於頁底之"輸入遠程注釋"欄位貼上此網址。請注意：若此數據通道源自上載檔案,分享以下網址給其他使用者可能讓其他使用者觀看上載檔案之<b>全部</b>內容。
END

 SHARE_INSTRUCTIONS_ALL_TRACKS => <<END,
如欲分享所有已選之數據通道給其他通用基因組瀏覽器，先複製以下網址，然後前往另外的基因組瀏覽器並於頁底之"輸入遠程注釋"欄位貼上此網址。請注意：若任何已選之數據通道源自上載檔案,分享以下網址給其他使用者可能讓其他使用者觀看上載檔案之<b>全部</b>內容。
END

 SHARE_DAS_INSTRUCTIONS_ONE_TRACK => <<END,
如欲透過<a href="http://www.biodas.org" target="_new">分佈式註釋系統
(Distributed Annotation System, DAS)</a> 分享此數據通道給其他通用基因組瀏覽器，先複製以下網址，然後前往另外的基因組瀏覽器並於輸入為新的DAS來源。<i>定量數據通道 ("wiggle"檔案)及上載檔案不能以DAS分享。</i>
END

 SHARE_DAS_INSTRUCTIONS_ALL_TRACKS => <<END,
如欲透過<a href="http://www.biodas.org" target="_new">分佈式註釋系統
(Distributed Annotation System, DAS)</a> 分享所有已選之數據通道給其他通用基因組瀏覽器，先複製以下網址，然後前往另外的基因組瀏覽器並於輸入為新的DAS來源。<i>定量數據通道 ("wiggle"檔案)及上載檔案不能以DAS分享。</i>
END

};
