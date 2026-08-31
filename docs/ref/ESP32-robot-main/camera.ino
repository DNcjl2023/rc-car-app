#include "soc/soc.h"             // disable brownout problems
#include "soc/rtc_cntl_reg.h"    // disable brownout problems

#include <DCMotor.h>
#include "stream.h"

#define MOTOR_1_PIN_1   14
#define MOTOR_1_PIN_2   15
#define MOTOR_1_PIN_EN  1
#define MOTOR_2_PIN_1   13
#define MOTOR_2_PIN_2   12
#define MOTOR_2_PIN_EN  2

#define MAX_SPEED 180

DCMotor motorLeft = DCMotor(MOTOR_1_PIN_1, MOTOR_1_PIN_2, MOTOR_1_PIN_EN);
DCMotor motorRight = DCMotor(MOTOR_2_PIN_1, MOTOR_2_PIN_2, MOTOR_2_PIN_EN);

int action_callback(char variable[32]) {
  Serial.println(variable);
  if (!strcmp(variable, "forward_right")) {
    //Serial.println("Forward-right");
    motorRight.on(MAX_SPEED / 3);
    motorLeft.on(MAX_SPEED);

  } else if (!strcmp(variable, "forward_left")) {
    //Serial.println("Forward-left");
    motorRight.on(MAX_SPEED);
    motorLeft.on(MAX_SPEED / 3);

  } else if (!strcmp(variable, "backward_right")) {
    //Serial.println("Backward-right");
    motorRight.on(-MAX_SPEED / 3);
    motorLeft.on(-MAX_SPEED);

  } else if (!strcmp(variable, "backward_left")) {
    //Serial.println("Backward-left");
    motorRight.on(-MAX_SPEED);
    motorLeft.on(-MAX_SPEED / 3);

  } else if(!strcmp(variable, "forward")) {
    //Serial.println("Forward");
    motorRight.on(MAX_SPEED);
    motorLeft.on(MAX_SPEED);

  } else if(!strcmp(variable, "backward")) {
    //Serial.println("Backward");
    motorRight.on(-MAX_SPEED);
    motorLeft.on(-MAX_SPEED);

  } else if(!strcmp(variable, "left")) {
    //Serial.println("Left");
    motorRight.on(-MAX_SPEED);
    motorLeft.on(MAX_SPEED);

  } else if(!strcmp(variable, "right")) {
    //Serial.println("Right");
    motorRight.on(MAX_SPEED);
    motorLeft.on(-MAX_SPEED);

  } else if(!strcmp(variable, "stop")) {
    //Serial.println("Stop");
    motorRight.on(0);
    motorLeft.on(0);

  } else {
    return -1;
  }
  return 0;
}


void setup() {
  WRITE_PERI_REG(RTC_CNTL_BROWN_OUT_REG, 0); //disable brownout detector 
  
  Serial.begin(115200);
  Serial.setDebugOutput(false);

  motorLeft.off();
  motorRight.off();

  initCameraServer();
  
  // Start streaming web server
  startCameraServer(action_callback);
}

void loop() {

}
