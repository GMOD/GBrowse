# do not remove the { } from the top and bottom of this page!!!
{

 CHARSET =>   'Big5',

   #----------
   # MAIN PAGE
   #----------

   PAGE_TITLE => '基因組流覽器',

   SEARCH_INSTRUCTIONS => <<END,
根據序列名﹐ 基因名﹐遺傳位點%s, 或其他標記進行查詢. 允許使用*通配符.
END

   NAVIGATION_INSTRUCTIONS => <<END,
點擊尺子使位點居中. 使用卷動/縮放按鈕改變放大倍數和位置. 要存下這一頁,
<a href="%s">設下書籤.</a>
END

   EDIT_INSTRUCTIONS => <<END,
在此編輯你的上載註釋數據. 你可用 tab鍵或空白分界,
但如果數據中有 tab 或空白﹐ 必須用引號.
END

   SHOWING_FROM_TO => '顯示 %s 起始于 %s, 位置從 %s 到 %s',

   INSTRUCTIONS      => '提示',

   HIDE              => '隱藏',

   SHOW              => '顯示',

   SHOW_INSTRUCTIONS => '顯示提示',

   LANDMARK => '標誌或區域',

   BOOKMARK => '設置書籤',

   GO       => '運行',

   FIND     => '尋找',

   SEARCH   => '查詢',

   DUMP     => '轉存',

   ANNOTATE     => '註釋',

   SCROLL   => '卷動/縮放',

   RESET    => '重置',

   DOWNLOAD_FILE    => '下載文件',

   DOWNLOAD_DATA    => '下載數據',

   DOWNLOAD         => '下載',

   DISPLAY_SETTINGS => '顯示設置',

   TRACKS   => '特征數據',

   EXTERNAL_TRACKS => '外部特征數據(斜體)',

   EXAMPLES => '範例',

   HELP     => '幫助',

   HELP_FORMAT => '幫助文件格式',

   CANCEL   => '取消',

   ABOUT    => '關於...',

   REDISPLAY   => '重新顯示',

   CONFIGURE   => '配置...',

   EDIT       => '編輯文件...',

   DELETE     => '刪除',

   EDIT_TITLE => '輸入/編輯註釋數據',

   IMAGE_WIDTH => '圖像寬度',

   BETWEEN     => '之間',

   BENEATH     => '下面',

   SET_OPTIONS => '設定特征數據選項...',

   UPDATE      => '更新圖像',

   DUMPS       => '轉存﹐ 查詢及其他選擇',

   DATA_SOURCE => '數據來源',

   UPLOAD_TITLE=> '上載註釋',

   UPLOAD_FILE => '上載文件',

   KEY_POSITION => '註解位置',

   BROWSE      => '流覽...',

   UPLOAD      => '上載',

   NEW         => '新...',

   REMOTE_TITLE => '增加遠程註釋',

   REMOTE_URL   => '輸入遠程註釋網址',

   UPDATE_URLS  => '上載網址',

   PRESETS      => '--選擇當前網址--',

   FILE_INFO    => '最近修改于 %s.  註釋標誌為: %s',

   FOOTER_1     => <<END,
注: 此頁利用 cookie 儲存相關信息. 無信息共享.
END

   FOOTER_2    => '通用基因組流覽器版本 %s',

   #----------------------
   # MULTIPLE MATCHES PAGE
   #----------------------

   HIT_COUNT      => '以下區域 %d 符合你的要求.',

   MATCHES_ON_REF => '符合于 %s',

   SEQUENCE        => '序列',

   SCORE           => '積分=%s',

   NOT_APPLICABLE => '無關',

   BP             => 'bp',

   #--------------
   # SETTINGS PAGE
   #--------------

   SETTINGS => '%s 的設置',

   UNDO     => '復原',

   REVERT   => '返回缺損值',

   REFRESH  => '更新屏幕',

   CANCEL_RETURN   => '取消改變並返回...',

   ACCEPT_RETURN   => '接受改變並返回...',

   OPTIONS_TITLE => '特征數據選項',

   SETTINGS_INSTRUCTIONS => <<END,
<i>顯示</i>負責打開和關閉路徑. <i>緊縮</i> 迫使路徑縮小以便註釋可以重迭. The <i>擴展</i> 和 <i>通過鏈接</i> 選項利用慢速和快速展開算法開啟碰撞控制. <i>擴展</i> 和 <i>標記</i> ﹐以及 <i>通過鏈接的擴展和標記l</i> 迫使註釋被標記上. 如果 選擇<i>自動</i> , 碰撞控制和標記選項 將會被自動選用. 如要改變路徑的順序﹐可使用 <i>改變路徑順序</i> 菜單. 如用限制註釋數量, 則改變 <i>極限</i> 的值.
END

   TRACK  => '特征數據',

   TRACK_TYPE => '特征數據類型',

   SHOW => '顯示',

   FORMAT => '格式',

   LIMIT  => '極限',

   ADJUST_ORDER => '調整順序',

   CHANGE_ORDER => '改變特征數據順序',

   AUTO => '自動',

   COMPACT => '緊縮',

   EXPAND => '擴展',

   EXPAND_LABEL => '擴展並標記',

   HYPEREXPAND => '通過鏈接擴展',

   HYPEREXPAND_LABEL =>'通過鏈接擴展並標記',

   NO_LIMIT    => '無極限',

   #--------------
   # HELP PAGES
   #--------------

   CLOSE_WINDOW => '關閉窗口',

   TRACK_DESCRIPTIONS => '特征數據的描述及引用',

   BUILT_IN           => '這個服務器的內部特征數據',

   EXTERNAL           => '外部註釋特征數據',

   ACTIVATE           => '請激活這個特征數據以便閱讀相關信息.',

   NO_EXTERNAL        => '沒有載入外部特徵.',

   NO_CITATION        => '無進一步相關信息.',

   #--------------
   # PLUGIN PAGES
   #--------------

 ABOUT_PLUGIN  => '關於 %s',

 BACK_TO_BROWSER => '返回流覽器',

 PLUGIN_SEARCH_1   => '%s (通過 %s 查詢)',

 PLUGIN_SEARCH_2   => '&lt;%s 查詢&gt;',

 CONFIGURE_PLUGIN   => '配置',

 BORING_PLUGIN => '這個插入軟件無額外配置.',

   #--------------
   # ERROR MESSAGES
   #--------------

 NOT_FOUND => '這個標誌 <i>%s</i> 無法識別. 請參閱幫助網頁.',

 TOO_BIG   => '詳細閱讀範圍局限於 %s 緘基.  點擊簡介並 選擇區域 %s bp 寬.',

 PURGED    => "找不到文件 %s.  可能已被刪除 ?.",

 NO_LWP    => "這個服務器不能獲取外部網址.",

 FETCH_FAILED  => "不能獲取 %s: %s.",

 TOO_MANY_LANDMARKS => '%d 標誌.  太多而列不出.',

 SMALL_INTERVAL    => '將區域縮小到 %s bp',

};

