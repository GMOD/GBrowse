# do not remove the { } from the top and bottom of this page!!!
# translated by Linus Taejoon Kwon (linusben <at> bawi <dot> org)
# Last modified : 2002-10-06

{

 CHARSET =>   'euc-kr',

   #----------
   # MAIN PAGE
   #----------

   PAGE_TITLE => 'Genome Browser',

   SEARCH_INSTRUCTIONS => <<END,
����(sequence) �̸��̳� ������ �̸�, locus %s, 
Ȥ�� �ٸ� ǥ��(landmark)�� ���� �˻���
�����մϴ�. ������ ���� �˻��� ���� *�� �����
�� �ֽ��ϴ�.
END

   NAVIGATION_INSTRUCTIONS => <<END,
��ġ�� ����� ���߱� ���ؼ��� ������ Ŭ���ϼ���. ��ũ��/�� ��ư��
����ϸ� Ȯ�� ������ ��ġ�� �ٲ� �� �ֽ��ϴ�. ������ ȭ���� 
�����ϰ� �����ø� <a href="%s">�� ��ũ</a>�� ���ã�⿡ �߰��ϼ���.
END

   EDIT_INSTRUCTIONS => <<END,
����ϰ��� �ϴ� annotation �����͸� ���⼭ �����ϼ���.
������ �ʵ带 �����ϱ� ���ؼ� ��(TAB)�̳� ������ ����Ͻ�
�� �ֽ��ϴ�. ���� ������ �����ϴ� �����Ͱ� �ִٸ� �ݵ�� 
���� ����ǥ�� ū ����ǥ�� ó���� ���ֽñ� �ٶ��ϴ�.
END

   SHOWING_FROM_TO => '�� %s ������ %s �� %s - %s ������ �����Դϴ�',

   INSTRUCTIONS      => '����',

   HIDE              => '�����',

   SHOW              => '�����ֱ�',

   SHOW_INSTRUCTIONS => '���� ����',

   HIDE_INSTRUCTIONS => '���� �����',

   SHOW_HEADER       => '���� ����',

   HIDE_HEADER       => '���� �����',
   
   LANDMARK => 'ǥ�� Ȥ�� ����',

   BOOKMARK => '���ã�� �߰�',

   IMAGE_LINK => '�̹��� ��ũ',

   SVG_LINK => '���ػ� �̹���',
   
   SVG_DESCRIPTION => <<END,
<p>
�� ��ũ�� �̹����� SVG(Scalable Vector Graphics) ��������
�����˴ϴ�. SVG �̹����� jpeg �̳� png �� ���� ������ �̷����
�̹������� �� ������ ���� ��� ������ ������ �ֽ��ϴ�.
</p>
<ul>
<li>�ػ� �ս� ���� �̹����� ũ�� ������ �����մϴ�.
<li>�Ϲ����� ���� ����� �׷��� ���α׷����� feature ���� ������ �����մϴ�.
<li>�ʿ��� �� �� ������ ���� EPS �������� ��ȯ�� �� �ֽ��ϴ�.
</ul>
<p>
SVG �̹����� ���� ���ؼ��� SVG ������ �����ϴ� �귯������ Adobe �翡��
�����ϴ� SVG ������ �÷�����, �Ǵ� SVG �̹����� ���� ������ �� �ִ�
Adobe Illustrator �� ���� ������ ���α׷��� �ʿ��մϴ�.
</p>
<p>
Adobe ���� SVG browser plugin: <a
href="http://www.adobe.com/support/downloads/product.jsp?product=46&platform=Macintosh">Macintosh</a>
| <a
href="http://www.adobe.com/support/downloads/product.jsp?product=46&platform=Windows">Windows</a>
<br />
Linux ����ڵ��� 
<a href="http://xml.apache.org/batik/">Batik SVG Viewer</a>�� ������.
</p>
<p>
<a href="%s" target="_blank">SVG �̹����� �� ������ â���� ���ϴ�</a></p>
<p>
�� �׸��� �ϵ� ��ũ�� �����Ϸ���, 
control-click (Macintosh) �Ǵ�  
���콺 ������ ��ư Ŭ�� (Windows) ���� �ٸ� �̸����� �׸� ������ �����ϼ���.
</p>   
END
   
     IMAGE_DESCRIPTION => <<END,
<p>
�� ȭ�鿡 ���Ե� �̹����� �ٸ� ������ ����ϰ� �ʹٸ�, �Ʒ���
URL �ּҸ� HTML �������� �����ؼ� �ٿ� ��������:
</p>
<pre>
&lt;IMAGE src="%s" /&gt;
</pre>
<p>
�� �̹����� ������ ���� ���� �̴ϴ�:
</p>
<p>
<img src="%s" />
</p>

<p>
���� �������� �׸�(chromosome �̳� contig view)�� ���δٸ�, 
������ ũ�⸦ �ٿ����ñ� �ٶ��ϴ�.
</p>
END

   TIMEOUT  => <<'END',
��û�� ���� �ð��� �ʰ��Ǿ����ϴ�. �ʹ� ���� ������ �����Ͻ� �� �����ϴ�.
��� ������ ������ �ʰ� �ϰų� ���� ������ �ٿ��� �ٽ� �õ��غ��ñ� �ٶ��ϴ�.
���� ��� �ð� �ʰ� ������ �߻��ϸ� ���� ���� "�ʱ�ȭ" ��ư�� ����������.
END 

   GO       => '����',

   FIND     => 'ã��',

   SEARCH   => '�˻�',

   DUMP     => '�����ޱ�(dump)',

   HIGHLIGHT => '���̶���Ʈ',

   ANNOTATE     => 'Annotate',

   SCROLL   => '�̵�/Ȯ��',

   RESET    => '�ʱ�ȭ',

   FLIP     => '������(flip)',
   
   DOWNLOAD_FILE    => '���� �����ޱ�',

   DOWNLOAD_DATA    => '������ �����ޱ�',

   DOWNLOAD         => '�����ޱ�',

   DISPLAY_SETTINGS => 'ȭ�� ����',

   TRACKS   => 'ǥ�� ����',

   EXTERNAL_TRACKS => '<i>(�ܺ� ������ ���ڸ����� ǥ�õ˴ϴ�)</i>',

   OVERVIEW_TRACKS => '<sup>*</sup>�������� ����',
   
   EXAMPLES => '����',

   HELP     => '����',

   HELP_FORMAT => '���� ������ ����',

   CANCEL   => '���',

   ABOUT    => '�߰� ����...',

   REDISPLAY   => '���� ��ħ',

   CONFIGURE   => '����...',

   EDIT       => '���� ����...',

   DELETE     => '���� ����',

   EDIT_TITLE => 'Anotation ���� �Է�/����',

   IMAGE_WIDTH => '�̹��� ����',

   BETWEEN     => '�߰��� ǥ��',

   BENEATH     => '�ؿ� ǥ��',

   LEFT        => '����',

   RIGHT       => '������',

   TRACK_NAMES => '���� �̸�ǥ',
   
   ALPHABETIC  => '���ĺ���',

   VARYING     => '������',
   
   SET_OPTIONS => 'ǥ�� ���� ����...',

   UPDATE      => '�׸� �ٽúθ���',

   DUMPS       => '�����ޱ�, �˻� �� ��Ÿ ���',

   DATA_SOURCE => '������ ��ó',

   UPLOAD_TRACKS=> '������ ���� �߰��ϱ�',

   UPLOAD_TITLE=> '���� annotation ���� ���',

   UPLOAD_FILE => '���� �ø���',

   KEY_POSITION => '���� ��� ��ġ',

   BROWSE      => '�˻�...',

   UPLOAD      => '�ø���',

   NEW         => '���� �����...',

   REMOTE_TITLE => '���� annotation ���� �߰�',

   REMOTE_URL   => '���� annotation ������ URL�� �Է��ϼ���',

   UPDATE_URLS  => 'URL ���� ����',

   PRESETS      => '--URL ����--',

   NO_TRACKS 	=> '*��������*',

   FILE_INFO    => '���� ���� %s.  annotation ǥ�� %s',

   FOOTER_1     => <<END,
�˸�: �� �������� ����� ������ �����ϰ� �о���̱� ���� cookie�� 
����մϴ�. ���� �̿��� �ٸ� ������ �������� �ʽ��ϴ�.
END

   FOOTER_2    => 'Generic genome browser ���� %s',

   #----------------------
   # MULTIPLE MATCHES PAGE
   #----------------------

   HIT_COUNT      => '%d ���� ������ �˻��Ǿ����ϴ�.',

   POSSIBLE_TRUNCATION =>  '�˻� ����� % ���� ���ѵǾ����ϴ�; ����� �������� �ʽ��ϴ�.',
   
   MATCHES_ON_REF => '%s�� ��ġ�մϴ�',

   SEQUENCE        => '����',

   SCORE           => 'score=%s',

   NOT_APPLICABLE => 'n/a',

   BP             => 'bp',

   #--------------
   # SETTINGS PAGE
   #--------------

   SETTINGS => '%s�� �����մϴ�',

   UNDO     => '���� ���� ���',

   REVERT   => '�⺻������',

   REFRESH  => '���� ��ħ',

   CANCEL_RETURN   => '���� ���� ����ϰ� ���ư���...',

   ACCEPT_RETURN   => '���� ���� �����ϰ� ���ư���...',

   OPTIONS_TITLE => '���� ����',

   SETTINGS_INSTRUCTIONS => <<END,
<i>����</i> üũ�ڽ��� �̿��Ͽ� ���� ���� ǥ�� ���θ� ������ 
�� �ֽ��ϴ�. <i>������</i> �ɼ��� ���� ������ ������ ���·� 
�����ֱ� ������ annotation ������ ��ġ�� �˴ϴ�. �� �� <i>Ȯ��</i>
�� <i>�߰� Ȯ��</i> �ɼ��� ����ϸ� ��ġ�� �κ��� ������ �� ��
�ֽ��ϴ�. <i>Ȯ�� �� �̸� ǥ��</i> �ɼǰ� <i>�߰� Ȯ�� �� 
�̸� ǥ��</i> �ɼ��� �����ϸ� annotation ������ ���� ǥ���� �� 
�ֽ��ϴ�. ���� <i>�ڵ�</i>�� �����Ѵٸ�, ������ ����ϴ� �ѵ� 
������ ��ħ �� �̸� ǥ�ð� �ڵ����� �̷�� ���ϴ�. ǥ�� ����
������ �����ϰ� �ʹٸ� <i>ǥ�� ���� ���� ����</i> �˾� �޴���
�̿��Ͽ� ������ �߰� ���� ������ annotation�� ������ �� �ֽ��ϴ�.
���� �������� annotation�� ���� �����ϱ� ���ؼ��� <i>����</i>
�޴��� ���� �����ϸ� �˴ϴ�.
END

   TRACK  => '���� ����',

   TRACK_TYPE => '���� ���� ����',

   SHOW => '����',

   FORMAT => '����',

   LIMIT  => '����',

   ADJUST_ORDER => '���� ����',

   CHANGE_ORDER => 'ǥ�� ���� ���� ����',

   AUTO => '�ڵ�',

   COMPACT => '������',

   EXPAND => 'Ȯ��',

   EXPAND_LABEL => 'Ȯ�� �� �̸� ǥ��',

   HYPEREXPAND => '�߰�Ȯ��',

   HYPEREXPAND_LABEL =>'�߰�Ȯ�� �� �̸� ǥ��',

   NO_LIMIT    => '���� ����',

   OVERVIEW    => '����(overview)',

   EXTERNAL    => '�ܺ�(external)',

   ANALYSIS    => '�м�',

   GENERAL     => '�Ϲ�(general)',

   DETAILS     => '����(details)',

   ALL_ON      => '��� �ѱ�',

   ALL_OFF     => '��� ����',
   
   #--------------
   # HELP PAGES
   #--------------

   CLOSE_WINDOW => 'â �ݱ�',

   TRACK_DESCRIPTIONS => '�߰� ���� ���� �� ���� �ڷ�',

   BUILT_IN           => '�� ������ ����� �߰� ����',

   EXTERNAL           => '�ܺ� annotation �߰� ����',

   ACTIVATE           => '������ ���� ���ؼ��� �� �߰� ������ �����ϼ���',

   NO_EXTERNAL        => '�ܺ� ����� �ҷ��� �� �����ϴ�.',

   NO_CITATION        => '�߰����� ������ �����ϴ�',

   #--------------
   # PLUGIN PAGES
   #--------------

 ABOUT_PLUGIN  => '%s �� ���Ͽ�',

 BACK_TO_BROWSER => '�������� ���ư���',

 PLUGIN_SEARCH_1   => '(%s �˻��� ����) %s',

 PLUGIN_SEARCH_2   => '&lt;%s �˻� &gt;',

 CONFIGURE_PLUGIN   => '����',

 BORING_PLUGIN => '�� �÷������� �߰����� ������ �� �� �����ϴ�',

   #--------------
   # ERROR MESSAGES
   #--------------

 NOT_FOUND => '<i>%s</i> ǥ�� ������ ã�� �� �����ϴ�. ���� ������ �����Ͻñ� �ٶ��ϴ�.',

 TOO_BIG   => '�ڼ��� ����� %s ���� ������� ������ �� �ֽ��ϴ�. %s ������ ���� �а� ���÷��� ��ü���⸦ Ŭ���ϼ���.',

 PURGED    => "%s ������ ã�� �� �����ϴ�.",

 NO_LWP    => "�� ������ �ܺ� URL�� ó���� �� �ֵ��� �������� �ʾҽ��ϴ�.",

 FETCH_FAILED  => "%s ������ ó���� �� �����ϴ�: %s.",

 TOO_MANY_LANDMARKS => '%d ���� ǥ���� �ʹ� ���� ǥ���� �� �����ϴ�.',

 SMALL_INTERVAL    => '���� ������ %s bp�� �������մϴ�',

 NO_SOURCES        => '���� �� �ִ� ������ �ҽ��� �����Ǿ� ���� �ʽ��ϴ�. �� �� �ִ� ������ �־����� ���� �� �����ϴ�.',

};
