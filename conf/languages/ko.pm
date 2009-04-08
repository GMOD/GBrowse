# do not remove the { } from the top and bottom of this page!!!
# translated by Linus Taejoon Kwon (linusben <at> bawi <dot> org)
# modified by Sue Rhee <rhee@acoma.stanford.edu>
# Last modified : 2008-5-05

{

 CHARSET =>   'euc-kr',

   #----------
   # MAIN PAGE
   #----------

   PAGE_TITLE => 'Genome Browser',

   SEARCH_INSTRUCTIONS => <<END,
서열(sequence) 이름이나 유전자 이름, locus %s, 
혹은 다른 표지(landmark)를 통해 검색이
가능합니다. 임의의 문자 검색을 위한 *를 사용할
수 있습니다.
END

   NAVIGATION_INSTRUCTIONS => <<END,
위치를 가운데로 맞추기 위해서는 눈금을 클릭하세요. 스크롤/줌 버튼을
사용하면 확대 정도와 위치를 바꿀 수 있습니다. 현재의 화면을 
저장하고 싶으시면 <a href="%s">이 링크</a>를 즐겨찾기에 추가하세요.
END

   EDIT_INSTRUCTIONS => <<END,
등록하고자 하는 annotation 데이터를 여기서 수정하세요.
각각의 필드를 구분하기 위해서 탭(TAB)이나 공백을 사용하실
수 있습니다. 만약 공백을 포함하는 데이터가 있다면 반드시 
작은 따옴표나 큰 따옴표로 처리를 해주시기 바랍니다.
END

   SHOWING_FROM_TO => '이 %s 정보는 %s 의 %s - %s 사이의 정보입니다',

   INSTRUCTIONS      => '설명',

   HIDE              => '숨기기',

   SHOW              => '보여주기',

   SHOW_INSTRUCTIONS => '설명 보기',

   HIDE_INSTRUCTIONS => '설명 숨기기',

   SHOW_HEADER       => '제목 보기',

   HIDE_HEADER       => '제목 숨기기',
   
   LANDMARK => '표지 혹은 영역',

   BOOKMARK => '즐겨찾기 추가',

   IMAGE_LINK => '이미지 링크',

   SVG_LINK => '고해상도 이미지',
   
   SVG_DESCRIPTION => <<END,
<p>
이 링크의 이미지는 SVG(Scalable Vector Graphics) 형식으로
생성됩니다. SVG 이미지는 jpeg 이나 png 와 같은 점으로 이루어진
이미지보다 몇 다음과 같은 몇가지 장점을 가지고 있습니다.
</p>
<ul>
<li>해상도 손실 없이 이미지의 크기 조절이 가능합니다.
<li>일반적인 백터 기반의 그래픽 프로그램에서 feature 별로 편집이 가능합니다.
<li>필요할 때 논문 출판을 위한 EPS 포멧으로 변환할 수 있습니다.
</ul>
<p>
SVG 이미지를 보기 위해서는 SVG 형식을 지원하는 브러우저나 Adobe 사에서
지원하는 SVG 브라우저 플러그인, 또는 SVG 이미지를 보고 편집할 수 있는
Adobe Illustrator 와 같은 별도의 프로그램이 필요합니다.
</p>
<p>
Adobe 사의 SVG browser plugin: <a
href="http://www.adobe.com/support/downloads/product.jsp?product=46&platform=Macintosh">Macintosh</a>
| <a
href="http://www.adobe.com/support/downloads/product.jsp?product=46&platform=Windows">Windows</a>
<br />
Linux 사용자들은 
<a href="http://xml.apache.org/batik/">Batik SVG Viewer</a>를 보세요.
</p>
<p>
<a href="%s" target="_blank">SVG 이미지를 새 브라우저 창에서 봅니다</a></p>
<p>
이 그림을 하드 디스크에 저장하려면, 
control-click (Macintosh) 또는  
마우스 오른쪽 버튼 클릭 (Windows) 이후 다른 이름으로 그림 저장을 선택하세요.
</p>   
END
   
     IMAGE_DESCRIPTION => <<END,
<p>
이 화면에 포함된 이미지를 다른 곳에서 사용하고 싶다면, 아래의
URL 주소를 HTML 페이지에 복사해서 붙여 넣으세요:
</p>
<pre>
&lt;IMAGE src="%s" /&gt;
</pre>
<p>
이 이미지는 다음과 같이 보일 겁니다:
</p>
<p>
<img src="%s" />
</p>

<p>
만약 개략적인 그림(chromosome 이나 contig view)만 보인다면, 
영역의 크기를 줄여보시기 바랍니다.
</p>
END

   TIMEOUT  => <<'END',
요청에 대한 시간이 초과되었습니다. 너무 넓은 영역을 선택하신 것 같습니다.
몇몇 정보를 보이지 않게 하거나 선택 영역을 줄여서 다시 시도해보시기 바랍니다.
만약 계속 시간 초과 문제가 발생하면 빨간 색의 "초기화" 버튼을 눌러보세요.
END 

   GO       => '실행',

   FIND     => '찾기',

   SEARCH   => '검색',

   DUMP     => '내려받기(dump)',

   HIGHLIGHT => '하이라이트',

   ANNOTATE     => 'Annotate',

   SCROLL   => '이동/확대',

   RESET    => '초기화',

   FLIP     => '뒤집기(flip)',
   
   DOWNLOAD_FILE    => '파일 내려받기',

   DOWNLOAD_DATA    => '데이터 내려받기',

   DOWNLOAD         => '내려받기',

   DISPLAY_SETTINGS => '화면 설정',

   TRACKS   => '표시 정보',

   EXTERNAL_TRACKS => '<i>(외부 정보는 이텔릭으로 표시됩니다)</i>',

   OVERVIEW_TRACKS => '<sup>*</sup>개략적인 정보',
   
   EXAMPLES => '예제',

   HELP     => '도움말',

   HELP_FORMAT => '파일 형식의 도움말',

   CANCEL   => '취소',

   ABOUT    => '추가 정보...',

   REDISPLAY   => '새로 고침',

   CONFIGURE   => '설정...',

   EDIT       => '파일 수정...',

   DELETE     => '파일 삭제',

   EDIT_TITLE => 'Anotation 정보 입력/편집',

   IMAGE_WIDTH => '이미지 넓이',

   BETWEEN     => '중간에 표시',

   BENEATH     => '밑에 표시',

   LEFT        => '왼쪽',

   RIGHT       => '오른쪽',

   TRACK_NAMES => '정보 이름표',
   
   ALPHABETIC  => '알파벳순',

   VARYING     => '설정순',
   
   SET_OPTIONS => '표시 정보 설정...',

   UPDATE      => '그림 다시부르기',

   DUMPS       => '내려받기, 검색 및 기타 기능',

   DATA_SOURCE => '데이터 출처',

   UPLOAD_TRACKS=> '나만의 정보 추가하기',

   UPLOAD_TITLE=> '개인 annotation 정보 등록',

   UPLOAD_FILE => '파일 올리기',

   KEY_POSITION => '정보 출력 위치',

   BROWSE      => '검색...',

   UPLOAD      => '올리기',

   NEW         => '새로 만들기...',

   REMOTE_TITLE => '원격 annotation 정보 추가',

   REMOTE_URL   => '원격 annotation 정보의 URL을 입력하세요',

   UPDATE_URLS  => 'URL 정보 갱신',

   PRESETS      => '--URL 선택--',

   NO_TRACKS 	=> '*정보없음*',

   FILE_INFO    => '최종 수정 %s.  annotation 표지 %s',

   FOOTER_1     => <<END,
알림: 이 페이지는 사용자 설정을 저장하고 읽어들이기 위해 cookie를 
사용합니다. 설정 이외의 다른 정보는 공유되지 않습니다.
END

   FOOTER_2    => 'Generic genome browser 버전 %s',

   #----------------------
   # MULTIPLE MATCHES PAGE
   #----------------------

   HIT_COUNT      => '%d 개의 영역이 검색되었습니다.',

   POSSIBLE_TRUNCATION =>  '검색 결과가 % 개로 제한되었습니다; 목록이 완전하지 않습니다.',
   
   MATCHES_ON_REF => '%s에 일치합니다',

   SEQUENCE        => '서열',

   SCORE           => 'score=%s',

   NOT_APPLICABLE => 'n/a',

   BP             => 'bp',

   #--------------
   # SETTINGS PAGE
   #--------------

   SETTINGS => '%s을 설정합니다',

   UNDO     => '변경 내용 취소',

   REVERT   => '기본값으로',

   REFRESH  => '새로 고침',

   CANCEL_RETURN   => '변경 내용 취소하고 돌아가기...',

   ACCEPT_RETURN   => '변경 내용 저장하고 돌아가기...',

   OPTIONS_TITLE => '선택 정보',

   SETTINGS_INSTRUCTIONS => <<END,
<i>보기</i> 체크박스를 이용하여 선택 정보 표시 여부를 결정할 
수 있습니다. <i>간단히</i> 옵션은 선택 정보를 간단한 형태로 
보여주기 때문에 annotation 정보가 겹치게 됩니다. 이 때 <i>확장</i>
과 <i>추가 확장</i> 옵션을 사용하면 겹치는 부분의 정보를 볼 수
있습니다. <i>확장 및 이름 표시</i> 옵션과 <i>추가 확장 및 
이름 표시</i> 옵션을 선택하면 annotation 정보를 같이 표시할 수 
있습니다. 만약 <i>자동</i>을 선택한다면, 여백이 허용하는 한도 
내에서 겹침 및 이름 표시가 자동으로 이루어 집니다. 표시 정보
순서를 변경하고 싶다면 <i>표시 정보 순서 변경</i> 팝업 메뉴를
이용하여 각각의 추가 정보 공간에 annotation을 지정할 수 있습니다.
현재 보여지는 annotation의 수를 제한하기 위해서는 <i>제한</i>
메뉴의 값을 변경하면 됩니다.
END

   TRACK  => '선택 정보',

   TRACK_TYPE => '선택 정보 종류',

   SHOW => '보기',

   FORMAT => '형식',

   LIMIT  => '제한',

   ADJUST_ORDER => '순서 결정',

   CHANGE_ORDER => '표시 정보 순서 변경',

   AUTO => '자동',

   COMPACT => '간단히',

   EXPAND => '확장',

   EXPAND_LABEL => '확장 및 이름 표시',

   HYPEREXPAND => '추가확장',

   HYPEREXPAND_LABEL =>'추가확장 및 이름 표시',

   NO_LIMIT    => '제한 없음',

   OVERVIEW    => '개요(overview)',

   EXTERNAL    => '외부(external)',

   ANALYSIS    => '분석',

   GENERAL     => '일반(general)',

   DETAILS     => '세부(details)',

   ALL_ON      => '모두 켜기',

   ALL_OFF     => '모두 끄기',
   
   #--------------
   # HELP PAGES
   #--------------

   CLOSE_WINDOW => '창 닫기',

   TRACK_DESCRIPTIONS => '추가 정보 설명 및 참고 자료',

   BUILT_IN           => '이 서버에 저장된 추가 정보',

   EXTERNAL           => '외부 annotation 추가 정보',

   ACTIVATE           => '정보를 보기 위해서는 이 추가 정보를 선택하세요',

   NO_EXTERNAL        => '외부 기능을 불러올 수 없습니다.',

   NO_CITATION        => '추가적인 정보가 없습니다',

   #--------------
   # PLUGIN PAGES
   #--------------

 ABOUT_PLUGIN  => '%s 에 대하여',

 BACK_TO_BROWSER => '브라우저로 돌아가기',

 PLUGIN_SEARCH_1   => '(%s 검색을 통한) %s',

 PLUGIN_SEARCH_2   => '&lt;%s 검색 &gt;',

 CONFIGURE_PLUGIN   => '설정',

 BORING_PLUGIN => '이 플러그인은 추가적인 설정을 할 수 없습니다',

   #--------------
   # ERROR MESSAGES
   #--------------

 NOT_FOUND => '<i>%s</i> 표지 정보를 찾을 수 없습니다. 도움말 정보를 참고하시기 바랍니다.',

 TOO_BIG   => '자세히 보기는 %s 개의 염기까지 적용할 수 있습니다. %s 영역을 보다 넓게 보시려면 전체보기를 클릭하세요.',

 PURGED    => "%s 파일을 찾을 수 없습니다.",

 NO_LWP    => "이 서버는 외부 URL을 처리할 수 있도록 설정되지 않았습니다.",

 FETCH_FAILED  => "%s 정보를 처리할 수 없습니다: %s.",

 TOO_MANY_LANDMARKS => '%d 개의 표지는 너무 많아 표시할 수 없습니다.',

 SMALL_INTERVAL    => '작은 간격을 %s bp로 재조정합니다',

 NO_SOURCES        => '읽을 수 있는 데이터 소스가 설정되어 있지 않습니다. 볼 수 있는 권한이 주어지지 않은 것 같습니다.',

   ABOUT => '에 관하여',

   ADD_YOUR_OWN_TRACKS => '당신의 선로를 추가하십시오',

   ALPHABETIC => '알파벳순',

   ANNOTATE => '현주하십시요',

   BACKGROUND_COLOR => '배경 색깔',

   BENEATH => '아래에',

   BETWEEN => '사이',

   BROWSE => '검색하십시요',

   CACHE_TRACKS => '선로를 저장하십시요',

   CANCEL => '취소하십시요',

   CHANGE => '전환하십시요',

   CLEAR_HIGHLIGHTING => '강조 표시를 제거하십시요',

   CONFIGURE => '형성하십시요',

   CONFIGURE_TRACKS => '선로를 형성하십시요',

   DATA_SOURCE => '데이터 송신부',

   DEFAULT => '디폴트',

   DELETE => '감소',

   DISPLAY_SETTINGS => '디스플레이 설정',

   DOWNLOAD => '다운받기',

   DOWNLOAD_DATA => '데이터를 다운받으십시요',

   DOWNLOAD_FILE => '파일을 다운받으십시요',

   DRAGGABLE_TRACKS => '끌을수있는선로들',

   DUMP => '덤프',

   DUMPS => '덤프들',

   DYNAMIC_VALUE => '동적한 수적인 양',

   EDIT => '편집',

   EDIT_TITLE => '편집제목',

   EXAMPLES => '예제들',

   EXTERNAL_TRACKS => '외부적의선로들',

   FEATURES_TO_HIGHLIGHT => '강조 표시를 할특징들',

   FEATURES_TO_HIGHLIGHT_HINT => '강조 표시를 할특징들 조언',

   FG_COLOR => '전면 색깔',

   FILE_INFO => '파일정보',

   FIND => '찾기',

   FLIP => '뒤집기',

   FOOTER_1 => '꼬리말',

   GLYPH => '글리프',

   GO => '가십시요',

   HEIGHT => '높이',

   HELP => '돕기',

   HELP_FORMAT => '도움서식',

   HIGHLIGHT => '강조표시',

   IMAGE_WIDTH => '그림너비',

   INVALID_SOURCE => '무효 출처',

   KEY_POSITION => '선로이름 자리',

   LEFT => '왼쪽',

   LINEWIDTH => '선너비',

   NEW => '새로운',

   NO_TRACKS => '선로 없음',

   OPTIONS_RESET => '옵션 복귀',

   OPTIONS_UPDATED => '옵션갱신?음',

   OVERVIEW_TRACKS => '선로개요',

   PACKING => '패킹',

   PRESETS => '사전 조절',

   REDISPLAY => '디스플레이 다시하기',

   REGION => '영역',

   REGIONS_TO_HIGHLIGHT => '강조표시할 영역',

   REGIONS_TO_HIGHLIGHT_HINT => '강조표시할 영역 조언',

   REGION_SIZE => '영역크기',

   REGION_TRACKS => '영역 선로들',

   REMOTE_TITLE => '원격제목',

   REMOTE_URL => '원격URL ',

   RESET => '복귀',

   RIGHT => '오른쪽',

   SCROLL => '스크롤',

   SEARCH => '찾기',

   SET_OPTIONS => '설정의옵션들',

   SHOW_GRID => '격자 눈금을 보이시요',

   SHOW_TOOLTIPS => '도구조언을보이시요',

   TRACKS => '선로들',

   TRACK_NAMES => '선로의 이름',

   UPDATE => '갱신하십시요',

   UPDATE_URLS => 'URL을 갱신하십시요',

   UPLOAD => '업로드',

   UPLOAD_FILE => '파일을 업로드하십시요',

   UPLOAD_TITLE => '제목을 업로드하십시요',

   UPLOAD_TRACKS => '선로를 업로드하십시요',

   VARYING => '다양한',

  CONFIGURE_THIS_TRACK => '<b>트랙세팅 (Track settings) 을 변경하기위하여 Click함</b>',

  NO_DAS  => 'Installation error (인스톨 에러):  DAS URL 작동하려면 Bio:DAS module을 반드시 인스톨해야 함.',

  OK  => 'OK (오 케이)',

  PDF_LINK => 'PDF 다운로드',

  PLUGIN_SEARCH => '%s plugin (플러그인)을 통한 검색',

  SEND_TO_GALAXY => '이 Region을 Galaxy에 보냄',

  SHARE_THIS_TRACK => '<b>이 track을 공유</b>',

  SHARE_ALL => '이 track들을 공유',

  SHARE => '공유 %s',

  SHOW_OR_HIDE_TRACK => '<b>이 track을 보이거나 숨김</b>',

  SHARE_DAS_INSTRUCTIONS_ONE_TRACK => '이 track을 <a href="http://www.biodas.org" target="_new"> Distributed Annotation System (DAS)</a>를 이용한 다른 genome browser와 공유하려면, 첫째 아래 URL을 복사하고, 다른 browser에 가서 이것을 새 DAS Source로 Enter (입력)함. <i>Quantitative tracks과 업로드된 파일은 DAS를 이용하여 공유할수 없음.</i>',

  SHARE_DAS_INSTRUCTIONS_ALL_TRACKS =>  '<a href="http://www.biodas.org" target="_new"> Distributed Annotation System (DAS)</a>를 이용하여 최근에 선택한 Track을 다른 genome browser와 공유하려면, 첫째 아래 URL을 복사하고 다른 browser에 가서 이것을 새 DAS Source로 Enter (입력)함. <i>Quantitative tracks과 업로드된 파일은 DAS를 이용하여 공유할수 없음.</i>',

  SHARE_INSTRUCTIONS_ONE_TRACK =>  '이 track을 다른 GBrowser genome browser와 공유하려면, 첫째 아래 URL을 복사하고, 다른 GBrowser에 가서 그 페이지 하단에 있는 “Enter Remote Annotation” field에 Paste함 (?여넣음). 만일 이 track이 업로드된 파일인 경우에는 이 URL을 다른 사용자와 공유할때 다른 <b>모든</b> 업로드된 data도 노출될 수 있다는 점을 유의하기 바람.',

  SHARE_INSTRUCTIONS_ALL_TRACKS => '최근에 선택한 track을 다른 GBrowser genome browser와 공유하려면, 첫째 아래 URL을 복사하고, 다른 GBrowser에 가서 그 페이지 하단에 있는 “Enter Remote Annotation” field에 Paste함 (?여넣음). 만일 이 선택한 track중 어느 하나가 업로드된 파일인 경우에는 이 URL을 다른 사용자와 공유할때 다른 <b>모든</b> 업로드된 data도 노출될 수 있다는 점을 유의하기 바람',

};
