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

   LANDMARK => '표지 혹은 영역',

   BOOKMARK => '즐겨찾기 추가',

   GO       => '실행',

   FIND     => '찾기',

   SEARCH   => '검색',

   DUMP     => '내려받기(dump)',

   ANNOTATE     => 'Annotate',

   SCROLL   => '이동/확대',

   RESET    => '초기화',

   DOWNLOAD_FILE    => '파일 내려받기',

   DOWNLOAD_DATA    => '데이터 내려받기',

   DOWNLOAD         => '내려받기',

   DISPLAY_SETTINGS => '화면 설정',

   TRACKS   => '표시 정보',

   EXTERNAL_TRACKS => '(외부 정보는 이텔릭으로 표시됩니다)',

   EXAMPLES => '예제',

   HELP     => '도움말',

   HELP_FORMAT => '파일 형식의 도움말',

   CANCEL   => '취소',

   ABOUT    => 'GBrowser는...',

   REDISPLAY   => '새로 고침',

   CONFIGURE   => '설정...',

   EDIT       => '파일 수정...',

   DELETE     => '파일 삭제',

   EDIT_TITLE => 'Anotation 정보 입력/편집',

   IMAGE_WIDTH => '이미지 넓이',

   BETWEEN     => '중간에 표시',

   BENEATH     => '밑에 표시',

   SET_OPTIONS => '표시 정보 설정...',

   UPDATE      => '그림 다시부르기',

   DUMPS       => '내려받기, 검색 및 기타 기능',

   DATA_SOURCE => '데이터 출처',

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

};
