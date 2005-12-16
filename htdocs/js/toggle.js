function turnOn (element) {
  element.style.display="inline";
}
function turnOff (element) {
  element.style.display="none";
}

function visibility (element_name,is_visible) {
   var element = document.getElementById(element_name);
   var show_control = document.getElementById(element_name + "_show");
   var hide_control = document.getElementById(element_name + "_hide");
   if (is_visible == 1) {
      turnOn(element);
      turnOff(show_control);
      turnOn(hide_control);
   } else {
      turnOff(element);
      turnOff(hide_control);
      turnOn(show_control);
   }
   setVisState(element_name,is_visible);
   return false;
}

function setVisState (element_name,is_visible) {
   var hidden_element = document.getElementById(element_name + "_vis");
   hidden_element.value = is_visible;
}

