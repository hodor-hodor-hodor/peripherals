#!/usr/bin/env python
import socket
import sys
import time

# This program reads values from the sonar and displays
# them on the leds.

def set_cmd(sock, set_str):
    sock.send(set_str)
    while True:
        retval = sock.recv(1)
        if retval == '\\':
            break

def get_cmd(sock, get_str):
    sock.send(get_str)
    data = ""
    while True:
        retval = sock.recv(1)
        if retval == '\\':
            break
        elif retval == '\n':
            pass
        else:
            data = data + retval

    return data


RANGE = 3
count = 0;

try:
    sock_sonar = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock_sonar.connect(('localhost', 8870))

    sock_led = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock_led.connect(('localhost', 8870))

    # Make sure we are talking to the correct serial port
    set_cmd(sock_sonar,'hbaset serial_fpga port /dev/ttyUSB1\n')

    # Make sure the sonar0 is turned on
    set_cmd(sock_sonar,'hbaset hba_sonar ctrl 1\n')

    time.sleep(0.5)

    # loop forever 
    while True:
        dist_str = get_cmd(sock_sonar,'hbaget hba_sonar sonar0\n')
        dist = int(dist_str, 16)
        print "dist: %d" % dist

        if dist < (RANGE*1):
            set_cmd(sock_led,'hbaset hba_basicio leds ' "%x" '\n' % 0x01)
        elif dist < (RANGE*2):
            set_cmd(sock_led,'hbaset hba_basicio leds ' "%x" '\n' % 0x03)
        elif dist < (RANGE*3):
            set_cmd(sock_led,'hbaset hba_basicio leds ' "%x" '\n' % 0x07)
        elif dist < (RANGE*4):
            set_cmd(sock_led,'hbaset hba_basicio leds ' "%x" '\n' % 0x0f)
        elif dist < (RANGE*5):
            set_cmd(sock_led,'hbaset hba_basicio leds ' "%x" '\n' % 0x1f)
        elif dist < (RANGE*6):
            set_cmd(sock_led,'hbaset hba_basicio leds ' "%x" '\n' % 0x3f)
        elif dist < (RANGE*7):
            set_cmd(sock_led,'hbaset hba_basicio leds ' "%x" '\n' % 0x7f)
        else:
            set_cmd(sock_led,'hbaset hba_basicio leds ' "%x" '\n' % 0xff)

        time.sleep(0.1)


except KeyboardInterrupt:
    # exit on Ctrl^C
    sock_sonar.close()
    sock_led.close()
    sys.exit()

except socket.error:
    print "Couldn't connect to hbaserver"
    sys.exit()

