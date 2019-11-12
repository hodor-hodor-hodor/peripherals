============================================================

HARDWARE

  The hba_servo peripheral controls hobby R/C servos.

RESOURCES

  center - Unsigned 8-bit offset value for servo position.
           default=128, min=0, max=255

  position - Unsigned 8-bit value for servo position.
             default=128, min=0, max=255

EXAMPLES
Adjust the servo center position offset.
Move servo to its CW and CCW extreams.
Center the servo.

 hbaset hba_servo center 120 
 hbaset hba_servo position 0
 hbaset hba_servo position 128
 hbaset hba_servo position 255

