#ifndef HTML_H
#define HTML_H

static const char PROGMEM INDEX_HTML[] = R"rawliteral(
<html>
  <head>
    <title>ESP32-CAM Robot</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
      body { font-family: Arial; text-align: center; margin:0px auto; padding-top: 30px;}
      table { width: 100%; margin-left: auto; margin-right: auto; }
      td { padding: 8px; width: 25%; height: 100px; } /* Set desired cell height */
      .button {
        background-color: #2f4468;
        border: none;
        color: white;
        padding: 10px 20px;
        text-align: center;
        text-decoration: none;
        display: inline-block;
        font-size: 18px;
        margin: 2px 2px;
        cursor: pointer;
        width: 100%; /* Full width of the cell */
        height: 100%; /* Full height of the cell */
        box-sizing: border-box; /* Include padding in button size */
        -webkit-touch-callout: none;
        -webkit-user-select: none;
        -khtml-user-select: none;
        -moz-user-select: none;
        -ms-user-select: none;
        user-select: none;
        -webkit-tap-highlight-color: rgba(0,0,0,0);
      }
      img { width: auto; max-width: 100%; height: auto; }
      .button:disabled {
        background-color: #999999;
        cursor: not-allowed;
      }
    </style>
  </head>
  <body>
    <h1>ESP32-CAM Robot</h1>
    <img src="" id="photo">
    <table>
      <tr>
        <td colspan="2" style="width: 50%;" align="center">
          <button id="forward" class="button" onmousedown="pressButton('forward');" ontouchstart="pressButton('forward');" onmouseup="releaseButton('forward');" ontouchend="releaseButton('forward')">Forward</button>
        </td>
        <td rowspan="2" style="width: 25%;" align="center">
          <button id="left" class="button" onmousedown="pressButton('left');" ontouchstart="pressButton('left');" onmouseup="releaseButton('left');" ontouchend="releaseButton('left')">Left</button>
        </td>
        <td rowspan="2" style="width: 25%;" align="center">
          <button id="right" class="button" onmousedown="pressButton('right');" ontouchstart="pressButton('right');" onmouseup="releaseButton('right');" ontouchend="releaseButton('right')">Right</button>
        </td>
      </tr>
      <tr>
        <td colspan="2" style="width: 50%;" align="center">
          <button id="backward" class="button" onmousedown="pressButton('backward');" ontouchstart="pressButton('backward');" onmouseup="releaseButton('backward');" ontouchend="releaseButton('backward')">Backward</button>
        </td>
      </tr>
      <tr>
        <td colspan="4" align="center">
          <button id="stop" class="button" onclick="sendStop();" onmousedown="sendStop();" ontouchstart="sendStop();">Stop</button>
        </td>
      </tr>
    </table>
    <script>
      // Track button states
      const state = { forward: false, backward: false, left: false, right: false };
      
      function pressButton(direction) {
        const button = document.getElementById(direction);
        if (button.disabled) return;  // Ignore if button is disabled

        state[direction] = true;
        updateButtons();
        sendAction();
      }
      
      function releaseButton(direction) {
        state[direction] = false;
        updateButtons();
        if (Object.values(state).every(v => !v)) sendStop();  // If all buttons are released, send stop
        else sendAction();
      }

      function sendAction() {
        let action = "";
        if (state.forward) action += "forward";
        if (state.backward) action += "backward";
        if (state.left) action += (action ? "_" : "") + "left";
        if (state.right) action += (action ? "_" : "") + "right";
        
        if (action) {
          const xhr = new XMLHttpRequest();
          xhr.open("GET", "/action?go=" + action, true);
          xhr.send();
        }
      }
      
      function sendStop() {
        const xhr = new XMLHttpRequest();
        xhr.open("GET", "/action?go=stop", true);
        xhr.send();
      }

      function updateButtons() {
        // Block backward if forward is active and vice versa
        document.getElementById("backward").disabled = state.forward || ((state.left || state.right) && !state.backward);
        document.getElementById("forward").disabled = state.backward || ((state.left || state.right) && !state.forward);
        
        // Block left if forward and right are active
        document.getElementById("left").disabled = state.right;
        
        // Block right if forward and left are active
        document.getElementById("right").disabled = state.left;
      }

      // Set the video stream source
      window.onload = function() {
        document.getElementById("photo").src = window.location.href.slice(0, -1) + ":81/stream";
      };
    </script>
  </body>
</html>


)rawliteral";

#endif // HTML_H