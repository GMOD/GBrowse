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

   LANDMARK => 'ǥ�� Ȥ�� ����',

   BOOKMARK => '���ã�� �߰�',

   GO       => '����',

   FIND     => 'ã��',

   SEARCH   => '�˻�',

   DUMP     => '�����ޱ�(dump)',

   ANNOTATE     => 'Annotate',

   SCROLL   => '�̵�/Ȯ��',

   RESET    => '�ʱ�ȭ',

   DOWNLOAD_FILE    => '���� �����ޱ�',

   DOWNLOAD_DATA    => '������ �����ޱ�',

   DOWNLOAD         => '�����ޱ�',

   DISPLAY_SETTINGS => 'ȭ�� ����',

   TRACKS   => 'ǥ�� ����',

   EXTERNAL_TRACKS => '(�ܺ� ������ ���ڸ����� ǥ�õ˴ϴ�)',

   EXAMPLES => '����',

   HELP     => '����',

   HELP_FORMAT => '���� ������ ����',

   CANCEL   => '���',

   ABOUT    => 'GBrowser��...',

   REDISPLAY   => '���� ��ħ',

   CONFIGURE   => '����...',

   EDIT       => '���� ����...',

   DELETE     => '���� ����',

   EDIT_TITLE => 'Anotation ���� �Է�/����',

   IMAGE_WIDTH => '�̹��� ����',

   BETWEEN     => '�߰��� ǥ��',

   BENEATH     => '�ؿ� ǥ��',

   SET_OPTIONS => 'ǥ�� ���� ����...',

   UPDATE      => '�׸� �ٽúθ���',

   DUMPS       => '�����ޱ�, �˻� �� ��Ÿ ���',

   DATA_SOURCE => '������ ��ó',

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

};
