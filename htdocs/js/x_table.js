// x_table.js, X v3.15.3, Cross-Browser.com DHTML Library
// Copyright (c) 2004 Michael Foster, Licensed LGPL (gnu.org)

/* Note:
  These may not work in Safari v1.2.
  Reference: http://www.quirksmode.org/dom/w3c_html.html
  Thanks Rob :-)
*/

/* xTableRowDisplay()
   bShow - if true show the row, else hide it
   sec - ID or element reference of table, tHead or tBody
   nRow - zero-based row number
*/
function xTableRowDisplay(bShow, sec, nRow)
{
  sec = xGetElementById(sec);
  if (sec && nRow < sec.rows.length) {
    sec.rows[nRow].style.display = bShow ? '' : 'none';
  }
}

/* xTableCellVisibility()
   bShow - if true show the cell, else hide it
   sec - ID or element reference of table, tHead or tBody
   nRow - zero-based row number
   nCol - zero-based column number
*/
function xTableCellVisibility(bShow, sec, nRow, nCol)
{
  sec = xGetElementById(sec);
  if (sec && nRow < sec.rows.length && nCol < sec.rows[nRow].cells.length) {
    sec.rows[nRow].cells[nCol].style.visibility = bShow ? 'visible' : 'hidden';
  }
}

/* xTableColDisplay()
   bShow - if true show the column, else hide it
   sec - ID or element reference of table, tHead or tBody
   nCol - zero-based column number
*/
function xTableColDisplay(bShow, sec, nCol)
{
  var r;
  sec = xGetElementById(sec);
  if (sec && nCol < sec.rows[0].cells.length) {
    for (r = 0; r < sec.rows.length; ++r) {
      sec.rows[r].cells[nCol].style.display = bShow ? '' : 'none';
    }
  }
}

/* xTableIterate()
   sec - ID or element reference of table, tHead, tBody, or tFoot
   fnCallback - function reference which will be called for
                for each row and cell in section. If fnCallback returns
                false then iterations will stop. It will be
                passed the following arguments:
                obj - reference to the current cell
                      or current row if isRow is true.
                isRow - true if obj is a ref to a TR,
                        false if obj is a ref to a TD.
                row - 0-based row number relative to section.
                col - 0-based column number relative to section.
                data - passed to fnCallback at each call
*/
function xTableIterate(sec, fnCallback, data)
{
  var r, c;
  sec = xGetElementById(sec);
  if (!sec || !fnCallback) { return; }
  for (r = 0; r < sec.rows.length; ++r) {
    if (false == fnCallback(sec.rows[r], true, r, c, data)) { return; }
    for (c = 0; c < sec.rows[r].cells.length; ++c) {
      if (false == fnCallback(sec.rows[r].cells[c], false, r, c, data)) { return; }
    }
  }
}

/* xTableCursor - mouseover highlight on rows and cells.
   id  - table id.
   inh - inherit style.
   def - default style.
   hov - row hover style.
   sel - cell selected style.
*/
function xTableCursor(id, inh, def, hov, sel) // object prototype
{
  var tbl = xGetElementById(id);
  if (tbl) {
    xTableIterate(tbl, init);
  }
  function init(obj, isRow)
  {
    if (isRow) {
      obj.className = def;
      obj.onmouseover = trOver;
      obj.onmouseout = trOut;
    }
    else {
      obj.className = inh;
      obj.onmouseover = tdOver;
      obj.onmouseout = tdOut;
    }
  }
  this.unload = function() { xTableIterate(tbl, done); }
  function done(o) { o.onmouseover = o.onmouseout = null; }
  function trOver() { this.className = hov; }
  function trOut() { this.className = def; }
  function tdOver() { this.className = sel; }
  function tdOut() { this.className = inh; }
}
