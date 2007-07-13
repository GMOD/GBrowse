function gbTurnOff (a) {
  if (document.getElementById(a+"_a")) { document.getElementById(a+"_a").checked='' };
  if (document.getElementById(a+"_n")) { document.getElementById(a+"_n").checked='' };
}

function gbCheck (button,state) {
  var a         = button.id;
  a             = a.substring(0,a.lastIndexOf("_"));
  var container = document.getElementById(a);
  if (!container) { return false; }
  var checkboxes = container.getElementsByTagName('input');
  if (!checkboxes) { return false; }
  for (var i=0; i<checkboxes.length; i++) {
     checkboxes[i].checked=state;
  }
  gbTurnOff(a);
  button.checked="on";
  return false;
}

function gbToggleTrack (button) {
  var track_name = button.value;
  var visible    = button.checked;
  var element    = document.getElementById("track_"+track_name);
  if (!element) { return false }
  if (visible) {
    element.style.display="block";
  } else {
    element.style.display="none";
  }
}

function update_segment (formdata) {
  var postData = 'render=detailview';
  if (formdata && formdata.length>0) {
      postData = postData + ';' + formdata
 }
  document.getElementById('panels').innerHTML='Loading...';
  new Ajax.Updater('panels',document.URL,
		   {method:'post',postBody:postData,evalScripts:true
		   }
                  );
}

function create_drag (div_name) {
  Sortable.create(
		  div_name,
		  {
		  constraint: 'vertical',
		      tag: 'div',
		      only: 'track',
		      handle: 'titlebar',
		      onUpdate: function() {
		      var postData = Sortable.serialize(div_name,{name:'label'});
		      new Ajax.Request(document.URL,{method:'post',postBody:postData});
		    }
		  }
		  );
}
