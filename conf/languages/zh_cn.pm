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

   PAGE_TITLE => '�����������',

   SEARCH_INSTRUCTIONS => <<END,
����ʹ�������������������Ŵ�λ�� %s ��������ǽ�������������ʹ��ͨ�����
END

   NAVIGATION_INSTRUCTIONS => <<END,
 ������ʹλ����С�ʹ�þ�/���Ű�ť�ı�Ŵ�����λ�á�
END

   EDIT_INSTRUCTIONS => <<END,
�ڴ˱༭���ϴ���ע�����ݡ�
����������Ʊ��(tabs) �� �ո��(spaces) ���ֽ�,
�������������еĿհ�����������õ����Ż�˫���Ű������ǡ�
END

   SHOWING_FROM_TO => '��ʾ %s ������ %s���� %s �� %s',

   INSTRUCTIONS      => '����',

   HIDE              => '����',

   SHOW              => '��ʾ',

   SHOW_INSTRUCTIONS => '��ʾ����',

   HIDE_INSTRUCTIONS => '���ؽ���',

   SHOW_HEADER       => '��ʾ����',

   HIDE_HEADER       => '���ر���',

   LANDMARK => '���',

   BOOKMARK => '��ӵ���ǩ',

   IMAGE_LINK => 'ͼ������',

   PDF_LINK=> '����PDF',

   SVG_LINK   => '������SVGͼ��',

   SVG_DESCRIPTION => <<END,
<p>
�����������ӽ�����SVG��ʽ��ͼ��SVG��ʽ��jpg��png��ʽ�и����ŵ㡣
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
Linux�û����Գ���ʹ�� <a href="http://xml.apache.org/batik/">Batik SVG �鿴��</a>.
</p>
<p>
<a href="%s" target="_blank">��������������в鿴SVGͼ��</a></p>
<p>
��control-click (Macintosh) ��
����Ҽ� (Windows) ��ѡ���ʵ�ѡ����Խ�ͼ�񱣴浽����������ϡ�
</p>   
END

   IMAGE_DESCRIPTION => <<END,
<p>
������Ƕ����ҳ��ͼ��, ���в�ճ��ͼ�����ַ��HTMLҳ��:
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
���ѡ����ʾ�Ź� (Ⱦɫ�� �� contig), �뾡����С�鿴����
</p>
END

   TIMEOUT  => <<'END',
����ʱ����ѡ����ʾ���������̫���������ʾ��
���Թص�һЩ����ͨ�� �� ѡ����С������.  �����δ����Ч���밴��ɫ�� "����" ��ť��
END

   GO       => 'ִ��',

   FIND     => 'Ѱ��',

   SEARCH   => '��ѯ',

   DUMP     => '��ӡ',

   HIGHLIGHT   => '��ɫ',

   ANNOTATE     => 'ע��',

   SCROLL   => '�ƶ�/����',

   RESET    => '����',

   FLIP     => '�ߵ�',

   DOWNLOAD_FILE    => '�����ļ�',

   DOWNLOAD_DATA    => '��������',

   DOWNLOAD         => '����',

   DISPLAY_SETTINGS => '��ʾ����',

   TRACKS   => '����ͨ��',

   EXTERNAL_TRACKS => '<i>�ⲿ����ͨ����б�壩</i>',

   OVERVIEW_TRACKS => '<sup>*</sup>����ͨ���Ź�',

   REGION_TRACKS => '<sup>**</sup>����ͨ������',

   EXAMPLES => '����',

   REGION_SIZE => '�����С (bp)',

   HELP     => '����',

   HELP_FORMAT => '�����ļ���ʽ',

   CANCEL   => 'ȡ��',

   ABOUT    => '����...',

   REDISPLAY   => '������ʾ',

   CONFIGURE   => '����...',

   CONFIGURE_TRACKS   => '��������ͨ��...',

   EDIT       => '�༭�ļ�...',

   DELETE     => 'ɾ���ļ�',

   EDIT_TITLE => '����/�༭ ע������',

   IMAGE_WIDTH => 'ͼ����',

   BETWEEN     => '֮��',

   BENEATH     => '����',

   LEFT        => '����',

   RIGHT       => '����',

   TRACK_NAMES => '����ͨ�����Ʊ�',

   ALPHABETIC  => '��ĸ',

   VARYING     => '�仯',

   SHOW_GRID    => '��ʾ����',

   SET_OPTIONS => '�趨����ͨ��ѡ��...',

   CLEAR_HIGHLIGHTING => '�����ɫ',

   UPDATE      => '����ͼ��',

   DUMPS       => '���棬��ѯ������ѡ��',

   DATA_SOURCE => '������Դ',

   UPLOAD_TRACKS=>'�ϴ����Լ�������ͨ��',

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

   FEATURES_TO_HIGHLIGHT => '��ɫ���� (����1 ����2...)',

   REGIONS_TO_HIGHLIGHT => '��ɫ���� (����1:��ʼ..���� ����2:��ʼ..����)',

   FEATURES_TO_HIGHLIGHT_HINT => '��ʾ: ������@color ѡ����ɫ, �� \'NUT21@lightblue\'',

   REGIONS_TO_HIGHLIGHT_HINT  => '��ʾ: ������@color ѡ����ɫ, �� \'Chr1:10000..20000@lightblue\'',

   NO_TRACKS    => '*�հ�*',

   FILE_INFO    => '����޸��� %s.  ע�ͱ�־: %s',

   FOOTER_1     => <<END,
ע��: ��ҳ��ʹ��cookies������ͻָ��û�ƫ����Ϣ��
�û���Ϣ����й¶��
END

   FOOTER_2    => 'ͨ�û�����������汾 %s',

   #----------------------
   # MULTIPLE MATCHES PAGE
   #----------------------

   HIT_COUNT      => '���� %d �����������Ҫ��',

   POSSIBLE_TRUNCATION  => '�����������Լ�� %d ������; �г��Ľ�����ܲ�����	��',

   MATCHES_ON_REF => '������; %s',

   SEQUENCE        => '����',

   SCORE           => '�÷�=%s',

   NOT_APPLICABLE => '������',

   BP             => 'bp',

   #--------------
   # SETTINGS PAGE
   #--------------

   SETTINGS => '%s ������',

   UNDO     => 'ȡ������',

   REVERT   => '�ָ�����ʼֵ',

   REFRESH  => 'ˢ��',

   CANCEL_RETURN   => 'ȡ�����Ĳ�����...',

   ACCEPT_RETURN   => '���ܸ��Ĳ�����...',

   OPTIONS_TITLE => '����ͨ��ѡ��',

   SETTINGS_INSTRUCTIONS => <<END,
<i>��ʾ</i> ��ѡ����Դ򿪻�ر�����ͨ����
<i>���</i> ѡ��ǿ��ѹ������ͨ����������Щע�ͻ��ص���<i>��չ</i> �� <i>ͨ��������չ</i>
ѡ�ÿ��ٻ����ٹ滮�㷨�����ƽ��������ԡ�<i>��չ</i> �� <i>���</i> �Լ� <i>ͨ�����ӵ���չ�ͱ�� </i> ѡ��ǿ��ע�ͱ���ǡ�
���ѡ����<i>�Զ�</i> ѡ��, �ռ�����������½������ݿ��ƺͱ��ѡ�������Ϊ�Զ���
Ҫ�ı�����ͨ����˳�����ʹ�� <i>��������ͨ��˳��</i> �����˵� ��Ϊ����ͨ������һ��ע��. Ҫ����ע�͵���Ŀ, �����
 <i>����</i> �˵���ֵ��
END

   TRACK  => '����ͨ��',

   TRACK_TYPE => '����ͨ������',

   SHOW => '��ʾ',

   FORMAT => '��ʽ',

   LIMIT  => '����',

   ADJUST_ORDER => '˳�����',

   CHANGE_ORDER => '��������ͨ��˳��',

   AUTO => '�Զ�',

   COMPACT => '���',#���� / ѹ��

   EXPAND => '��չ',

   EXPAND_LABEL => '��չ�����',

   HYPEREXPAND => 'ͨ��������չ',

   HYPEREXPAND_LABEL =>'ͨ��������չ�����',

   NO_LIMIT    => '������',

   OVERVIEW    => '�Ź�',

   EXTERNAL    => '�ⲿ��',

   ANALYSIS    => '����',

   GENERAL     => 'һ��',

   DETAILS     => 'ϸ��',

   REGION      => '����',

   ALL_ON      => 'ȫ��',

   ALL_OFF     => 'ȫ��',

   #--------------
   # HELP PAGES
   #--------------

   CLOSE_WINDOW => '�رմ���',

   TRACK_DESCRIPTIONS => '����ͨ��������������',

   BUILT_IN           => '������������ڵ�����ͨ��',

   EXTERNAL           => '�ⲿע������ͨ��',

   ACTIVATE           => '�뼤�������ͨ�����鿴�����Ϣ',

   NO_EXTERNAL        => 'û�������ⲿ����',

   NO_CITATION        => 'û�ж���������Ϣ.',

   #--------------
   # PLUGIN PAGES
   #--------------

 ABOUT_PLUGIN  => '���� %s',

 BACK_TO_BROWSER => '���ص������',

 PLUGIN_SEARCH   => '%s (ͨ�� %s ����)',

 #PLUGIN_SEARCH  => 'search via the %s plugin'
 #PLUGIN_SEARCH_1   => '%s (ͨ�� %s ����)',
 #PLUGIN_SEARCH_2   => '&lt;%s ��ѯ&gt;',

 CONFIGURE_PLUGIN   => '����',

 BORING_PLUGIN => '�˲�������������',

   #--------------
   # ERROR MESSAGES
   #--------------

 NOT_FOUND => '�޷�ʶ����Ϊ <i>%s</i> �ı�־�� ��鿴����ҳ�档',

 TOO_BIG   => '�鿴��Χ������ %s �����ϸ�ڡ�  �ڸ����е��ѡ�� %s �������.',

 PURGED    => "�Ҳ����ļ� %s ��  �����ѱ�ɾ��?",

 NO_LWP    => "�˷�������֧�ֻ�ȡ�ⲿ��ַ",

 FETCH_FAILED  => "���ܻ�ȡ %s: %s.",

 TOO_MANY_LANDMARKS => '%d ��־����־̫��δ��ȫ����ʾ��',

 SMALL_INTERVAL    => '��������С�� %s bp',

 NO_SOURCES        => 'û�����ÿɶ�ȡ������Դ.  ������û��Ȩ�޲鿴����',

# Missed Terms

 ADD_YOUR_OWN_TRACKS => '������Լ���ͨ������',

 INVALID_SOURCE    => '��Դ %s ������.',

 BACKGROUND_COLOR  => '�����ɫ',

 FG_COLOR          => '������ɫ',

 HEIGHT           => '�߶�',

 PACKING          => '��װ',

 GLYPH            => '��ʽ',

 LINEWIDTH        => '�������',

 DEFAULT          => '(��ʼ״̬)',

 DYNAMIC_VALUE    => '��̬����ֵ',

 CHANGE           => '����',

 DRAGGABLE_TRACKS  => '����ҷ����ͨ��',

 CACHE_TRACKS      => '����ͨ������',

 CHANGE_DEFAULT  => '���ĳ�ʼֵ',

 SHOW_TOOLTIPS     => '��ʾ������ʾ',

 OPTIONS_RESET     => '����ҳ�����ûָ�����ʼֵ',

 OPTIONS_UPDATED   => '�µ�վ��������Ч; ����ҳ�������ѻָ�����ʼֵ',
 
SEND_TO_GALAXY    => '���ʹ�������Galaxy',
#Galaxy http://main.g2.bx.psu.edu/

 NO_DAS            => '��װ����: �����Ȱ�װBio::Das ģ�����ִ��DAS ��ַ����֪ͨ��վ����Ա��',

 SHOW_OR_HIDE_TRACK => '<b>��ʾ�����ش�����ͨ��</b>',

 CONFIGURE_THIS_TRACK   => '<b>���˸�������ͨ���趨��</b>',

 SHARE_THIS_TRACK   => '<b>���������ͨ��</b>',

 SHARE_ALL          => '������Щ����ͨ��',

 SHARE              => '���� %s',

 SHARE_INSTRUCTIONS_ONE_TRACK => <<END,
�������������ͨ��������ͨ�û�������������ȸ���������ַ��Ȼ��ǰ������Ļ�������������ҳ��֮"����Զ��ע��"��λ���ϴ���ַ����ע�⣺��������ͨ��Դ�����ص���,����������ַ������ʹ���߿���������ʹ���߹ۿ����ص���֮<b>ȫ��</b>���ݡ�
END

 SHARE_INSTRUCTIONS_ALL_TRACKS => <<END,
��������������ѡ֮����ͨ��������ͨ�û�������������ȸ���������ַ��Ȼ��ǰ������Ļ�������������ҳ��֮"����Զ��ע��"��λ���ϴ���ַ����ע�⣺���κ���ѡ֮����ͨ��Դ�����ص���,����������ַ������ʹ���߿���������ʹ���߹ۿ����ص���֮<b>ȫ��</b>���ݡ�
END

 SHARE_DAS_INSTRUCTIONS_ONE_TRACK => <<END,
����͸��<a href="http://www.biodas.org" target="_new">�ֲ�ʽע��ϵͳ
(Distributed Annotation System, DAS)</a> ���������ͨ��������ͨ�û�������������ȸ���������ַ��Ȼ��ǰ������Ļ�����������������Ϊ�µ�DAS��Դ��<i>��������ͨ�� ("wiggle"����)�����ص���������DAS����</i>
END

 SHARE_DAS_INSTRUCTIONS_ALL_TRACKS => <<END,
����͸��<a href="http://www.biodas.org" target="_new">�ֲ�ʽע��ϵͳ
(Distributed Annotation System, DAS)</a> ����������ѡ֮����ͨ��������ͨ�û�������������ȸ���������ַ��Ȼ��ǰ������Ļ�����������������Ϊ�µ�DAS��Դ��<i>��������ͨ�� ("wiggle"����)�����ص���������DAS����</i>
END

};

