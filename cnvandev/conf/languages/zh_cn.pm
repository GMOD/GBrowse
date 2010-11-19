# do not remove the { } from the top and bottom of this page!!!
#Simple_Chinese language module by Li DaoFeng <lidaof@cau.edu.cn>
#Modified from Tradition_Chinese version by Jack Chen <chenn@cshl.edu>
{

 CHARSET =>   'GB2312',

   #----------
   # MAIN PAGE
   #----------

   PAGE_TITLE => '�����������',

   SEARCH_INSTRUCTIONS => <<END,
����ʹ�������������������Ŵ�λ�� %s ��������ǽ�������������ʹ��ͨ�����
END

   NAVIGATION_INSTRUCTIONS => <<END,
 ������ʹλ����С�ʹ�þ�/���Ű�ť�ı�Ŵ�����λ�á�
END

   EDIT_INSTRUCTIONS => <<END,
�ڴ˱༭���ϴ���ע�����ݡ�
��������ñ���(tabs) �� �ո��(spaces) ���ֽ�,
�������������еĿհ�����������õ����Ż�˫���Ű������ǡ�
END

   SHOWING_FROM_TO => '��%s ����ʾ %s, λ�ô� %s �� %s',

   INSTRUCTIONS      => '����',

   HIDE              => '����',

   SHOW              => '��ʾ',

   SHOW_INSTRUCTIONS => '��ʾ����',

   HIDE_INSTRUCTIONS => '���ؽ���',

   SHOW_HEADER       => '��ʾ����',

   HIDE_HEADER       => '���ر���',

   LANDMARK => '��־������',

   BOOKMARK => '��ӵ���ǩ',

   IMAGE_LINK => 'ͼ������',

   SVG_LINK   => '������ͼ��',

   SVG_DESCRIPTION => <<END,
<p>
��������ӽ�����SVG��ʽ��ͼ��SVG��ʽ�Ա�jpg��png��ʽ������ŵ㡣
</p>
<ul>
<li>��Ӱ��ͼ������������¸ı�ͼ���С
<li>��������ͨͼ��������б༭
<li>�������Ҫ����ת����EPS��ʽ������֮�á�
</ul>
<p>
Ҫ��ʾSVGͼ��, ��Ҫ�����֧��SVG, �������ʹ��Adobe SVG ��������, ���� Adobe Illustrator��SVG�Ĳ鿴�ͱ༭�����
</p>
<p>
Adobe�� SVG ��������: <a
href="http://www.adobe.com/support/downloads/product.jsp?product=46&platform=Macintosh">Macintosh</a>
| <a
href="http://www.adobe.com/support/downloads/product.jsp?product=46&platform=Windows">Windows</a>
<br />
Linux�û����Գ��� <a href="http://xml.apache.org/batik/">Batik SVG �鿴��</a>.
</p>
<p>
<a href="%s" target="_blank">��������������в鿴SVGͼ��</a></p>
<p>
��control-click (Macintosh) ��
����Ҽ� (Windows) ��ѡ���ʵ�ѡ�����ͼ�񱣴浽���̡�
</p>   
END

   IMAGE_DESCRIPTION => <<END,
<p>
����Ƕ����ҳ��ͼ��, ���в�ճ��ͼ���URL��HTMLҳ��:
</p>
<pre>
&lt;IMAGE src="%s" /&gt;
</pre>
<p>
ͼ������Ӧ��������:
</p>
<p>
<img src="%s" />
</p>

<p>
���ѡ����ʾ��Ҫ (Ⱦɫ�� �� contig), ������С�鿴����
</p>
END

   TIMEOUT  => <<'END',
����ʱ����ѡ����ʾ���������̫���������ʾ��
���Թص�һЩ���ݵ� �� ѡ����С������.  �����Ȼ��ʱ���밴��ɫ�� "����" ��ť��
END

   GO       => 'ִ��',

   FIND     => 'Ѱ��',

   SEARCH   => '��ѯ',

   DUMP     => '��ʾ',

   HIGHLIGHT   => '����',

   ANNOTATE     => 'ע��',

   SCROLL   => '��/����',

   RESET    => '����',

   FLIP     => '�ߵ�',

   DOWNLOAD_FILE    => '�����ļ�',

   DOWNLOAD_DATA    => '��������',

   DOWNLOAD         => '����',

   DISPLAY_SETTINGS => '��ʾ����',

   TRACKS   => '���ݵ�',

   EXTERNAL_TRACKS => '<i>�ⲿ���ݵ���б�壩</i>',

   OVERVIEW_TRACKS => '<sup>*</sup>���ݵ���Ҫ',

   REGION_TRACKS => '<sup>**</sup>���ݵ�����',

   EXAMPLES => '����',

   REGION_SIZE => '�����С (bp)',

   HELP     => '����',

   HELP_FORMAT => '�����ļ���ʽ',

   CANCEL   => 'ȡ��',

   ABOUT    => '����...',

   REDISPLAY   => '������ʾ',

   CONFIGURE   => '����...',

   CONFIGURE_TRACKS   => '�������ݵ�...',

   EDIT       => '�༭�ļ�...',

   DELETE     => 'ɾ���ļ�',

   EDIT_TITLE => '����/�༭ ע������',

   IMAGE_WIDTH => 'ͼ����',

   BETWEEN     => '֮��',

   BENEATH     => '����',

   LEFT        => '����',

   RIGHT       => '����',

   TRACK_NAMES => '���ݵ����Ʊ�',

   ALPHABETIC  => '��ĸ',

   VARYING     => '�仯',

   SHOW_GRID    => '��ʾ����',

   SET_OPTIONS => '�趨��������ѡ��...',

   CLEAR_HIGHLIGHTING => '�������',

   UPDATE      => '����ͼ��',

   DUMPS       => '���棬��ѯ������ѡ��',

   DATA_SOURCE => '������Դ',

   UPLOAD_TRACKS=>'�ϴ����Լ������ݵ�',

   UPLOAD_TITLE=> '�ϴ����Լ���ע��',

   UPLOAD_FILE => '�ϴ�һ���ļ�',

   KEY_POSITION => 'ע��λ��',

   BROWSE      => '���...',

   UPLOAD      => '�ϴ�',

   NEW         => '����...',

   REMOTE_TITLE => '���Զ��ע��',

   REMOTE_URL   => '����Զ��ע����ַ',

   UPDATE_URLS  => '������ַ',

   PRESETS      => '--ѡ��ǰ��ַ--',

   FEATURES_TO_HIGHLIGHT => '�������� (����1 ����2...)',

   REGIONS_TO_HIGHLIGHT => '�������� (����1:��ʼ..���� ����2:��ʼ..����)',

   FEATURES_TO_HIGHLIGHT_HINT => '��ʾ: ������@color ѡ����ɫ, �� \'NUT21@lightblue\'',

   REGIONS_TO_HIGHLIGHT_HINT  => '��ʾ: ������@color ѡ����ɫ, �� \'Chr1:10000..20000@lightblue\'',

   NO_TRACKS    => '*�հ�*',

   FILE_INFO    => '����޸� %s.  ע�ͱ�־: %s',

   FOOTER_1     => <<END,
Note: This page uses cookies to save and restore preference information.
No information is shared.
END

   FOOTER_2    => 'Generic genome browser version %s',

   #----------------------
   # MULTIPLE MATCHES PAGE
   #----------------------

   HIT_COUNT      => '���� %d �����������Ҫ��',

   POSSIBLE_TRUNCATION  => '��������������� %d ��; ����б���ܲ���ȫ��',

   MATCHES_ON_REF => '������ %s',

   SEQUENCE        => '����',

   SCORE           => '�÷�=%s',

   NOT_APPLICABLE => '�޹� ',

   BP             => 'bp',

   #--------------
   # SETTINGS PAGE
   #--------------

   SETTINGS => '%s ������',

   UNDO     => '��������',

   REVERT   => '�ظ���Ĭ��ֵ',

   REFRESH  => 'ˢ��',

   CANCEL_RETURN   => 'ȡ�����Ĳ�����...',

   ACCEPT_RETURN   => '���ܸ��Ĳ�����...',

   OPTIONS_TITLE => '��������ѡ��',

   SETTINGS_INSTRUCTIONS => <<END,
<i>��ʾ</i> ��ѡ�����ִ�����ݵ��Ĵ򿪺͹رա� The
<i>����</i> ѡ��ǿ�ƽ������ݵ���������Щע�ͻ��ص���<i>��չ</i> �� <i>ͨ������</i>
ѡ�����ÿ��ٻ����ٹ滮�㷨���������ơ�<i>��չ</i> �� <i>���</i> �Լ� <i>ͨ�����ӵ���չ�ͱ�� </i> ѡ��ǿ��ע�ͱ���ǡ�
���ѡ����<i>�Զ�</i> ѡ��, �ռ��������������ײ���ƺͱ��ѡ�������Ϊ�Զ���
Ҫ�ı����ݵ���˳�����ʹ�� <i>�������ݵ�˳��</i> �����˵� ��Ϊ���ݵ�����һ��ע��. Ҫ����ע�͵���Ŀ, ����
 <i>����</i> �˵���ֵ��
END

   TRACK  => '���ݵ�',

   TRACK_TYPE => '���ݵ�����',

   SHOW => '��ʾ',

   FORMAT => '��ʽ',

   LIMIT  => '����',

   ADJUST_ORDER => '˳�����',

   CHANGE_ORDER => '�������ݵ�˳��',

   AUTO => '�Զ�',

   COMPACT => '����',

   EXPAND => '��չ',

   EXPAND_LABEL => '��չ�����',

   HYPEREXPAND => 'ͨ��������չ',

   HYPEREXPAND_LABEL =>'ͨ��������չ�����',

   NO_LIMIT    => '������',

   OVERVIEW    => '��Ҫ',

   EXTERNAL    => '�ⲿ��',

   ANALYSIS    => '����',

   GENERAL     => '��Ҫ',

   DETAILS     => 'ϸ��',

   REGION      => '����',

   ALL_ON      => 'ȫ����',

   ALL_OFF     => 'ȫ���ر�',

   #--------------
   # HELP PAGES
   #--------------

   CLOSE_WINDOW => '�رմ���',

   TRACK_DESCRIPTIONS => '�������ݵ�����������',

   BUILT_IN           => '������������ڵ���������',

   EXTERNAL           => '�ⲿע����������',

   ACTIVATE           => '�뼤����������ݲ��鿴�����Ϣ',

   NO_EXTERNAL        => 'û�������ⲿ����',

   NO_CITATION        => 'û�ж���������Ϣ.',

   #--------------
   # PLUGIN PAGES
   #--------------

 ABOUT_PLUGIN  => '���� %s',

 BACK_TO_BROWSER => '���ص������',

 PLUGIN_SEARCH_1   => '%s (ͨ�� %s ����)',

 PLUGIN_SEARCH_2   => '&lt;%s ��ѯ&gt;',

 CONFIGURE_PLUGIN   => '����',

 BORING_PLUGIN => '�˲�������������',

   #--------------
   # ERROR MESSAGES
   #--------------

 NOT_FOUND => '�޷�ʶ����Ϊ <i>%s</i> �ı�־�� ��鿴����ҳ�档',

 TOO_BIG   => 'ϸ�ڲ鿴��Χ������ %s �����  �ڸ�Ҫ�е��ѡ�� %s �������.',

 PURGED    => "�Ҳ����ļ� %s ��  �����ѱ�ɾ��?",

 NO_LWP    => "�˷�������֧�ֻ�ȡ�ⲿ��ַ",

 FETCH_FAILED  => "���ܻ�ȡ %s: %s.",

 TOO_MANY_LANDMARKS => '%d ��־�� ̫����в�������',

 SMALL_INTERVAL    => '��������С�� %s bp',

 NO_SOURCES        => 'û�����ÿɶ�������Դ.  ������û��Ȩ�޲鿴����',

};
