/*
 *  Name: hba_servo.c
 *
 *  Description: HomeBrew Automation (hba) servo peripheral
 *
 *  Resources:
 *    center    -  current value at the four SERVO pins
 *    position  -  SERVO data direction. 1==output, default==input
 */

/*
 * Copyright:   Copyright (C) 2019 by Demand Peripherals, Inc.
 *              All rights reserved.
 *
 * License:     This program is free software; you can redistribute it and/or
 *              modify it under the terms of the Version 2 of the GNU General
 *              Public License as published by the Free Software Foundation.
 *              GPL2.txt in the top level directory is a copy of this license.
 *              This program is distributed in the hope that it will be useful,
 *              but WITHOUT ANY WARRANTY; without even the implied warranty of
 *              MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *              GNU General Public License for more details. 
 */

/*
 * FPGA Register Interface
 *   reg0: Center - Servo 0
 *   reg1: Position - Servo 0
 */

#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdint.h>
#include <syslog.h>
#include <errno.h>
#include <string.h>
#include <sys/fcntl.h>
#include <sys/types.h>
#include <limits.h>              // for PATH_MAX
#include <termios.h>
#include <dlfcn.h>
#include "eedd.h"
#include "hba.h"
#include "readme.h"


/**************************************************************
 *  - Limits and defines
 **************************************************************/
        // Hardware register definitions
#define HBA_SERVO_REG_CENTER   (0)
#define HBA_SERVO_REG_POSITION (1)
        // resource names and numbers
#define FN_CENTER          "center"
#define FN_POSITION        "position"
#define RSC_CENTER         0
#define RSC_POSITION       1
        // What we are is a ...
#define PLUGIN_NAME        "hba_servo"
        // Default data direction is zero, is all inputs
#define HBA_DEF_CENTER     128
        // Default is no interrupt pin enabled
#define HBA_DEF_POSITION   128
        // Maximum size of input/output string
#define MX_MSGLEN          120


/**************************************************************
 *  - Data structures
 **************************************************************/
    // All state info for an instance of a SERVO port
typedef struct
{
    int      parent;   // Slot number of parent peripheral.
    int      coreid;   // FPGA core ID with this BASICIO
    void    *pslot;    // handle to plug-in's's slot info
    int      center;   // most recent value on servo pins
    int      position; // SERVO data direction. 1==output
    int      (*sendrecv_pkt)();  // routine to send data to the FPGA
} HBA_SERVO;


/**************************************************************
 *  - Function prototypes
 **************************************************************/
static void usercmd(int, int, char*, SLOT*, int, int*, char*);
extern SLOT Slots[];

/**************************************************************
 * Initialize():  - Allocate our permanent storage and set up
 * the read/write callbacks.
 **************************************************************/
int Initialize(
    SLOT *pslot)         // points to the SLOT for this plug-in
{
    HBA_SERVO *pctx;        // our local context
    const char *errmsg;     // error message from dlsym

    // Allocate memory for this plug-in
    pctx = (HBA_SERVO *) malloc(sizeof(HBA_SERVO));
    if (pctx == (HBA_SERVO *) 0) {
        // Malloc failure this early?
        edlog("memory allocation failure in hba_servo initialization");
        return (-1);
    }

    // Init our HBA_SERVO structure
    pctx->parent = hba_parent();       // Slot number of parent peripheral.
    pctx->coreid = HBA_SERVO_COREID; // Immutable.
    pctx->pslot = pslot;               // this instance of a servo

    pctx->center   = HBA_DEF_CENTER;   // default data direction rate
    pctx->position = HBA_DEF_POSITION; // default interrupt enable

    // Register name and private data
    pslot->name = PLUGIN_NAME;
    pslot->priv = pctx;
    pslot->desc = "HomeBrew Automation SERVO port";
    pslot->help = README;

    // Add handlers for the user visible resources
    pslot->rsc[RSC_CENTER].slot = pslot;
    pslot->rsc[RSC_CENTER].name = FN_CENTER;
    pslot->rsc[RSC_CENTER].flags = IS_READABLE | IS_WRITABLE;
    pslot->rsc[RSC_CENTER].bkey = 0;
    pslot->rsc[RSC_CENTER].pgscb = usercmd;
    pslot->rsc[RSC_CENTER].uilock = -1;

    pslot->rsc[RSC_POSITION].slot = pslot;
    pslot->rsc[RSC_POSITION].name = FN_POSITION;
    pslot->rsc[RSC_POSITION].flags = IS_READABLE | IS_WRITABLE;
    pslot->rsc[RSC_POSITION].bkey = 0;
    pslot->rsc[RSC_POSITION].pgscb = usercmd;
    pslot->rsc[RSC_POSITION].uilock = -1;

    // The serial_fpga plug-in has a routine to send packets to the FPGA
    // and to return with packet data from the FPGA.  We need to look up
    // this, 'sendrecv_pkt', address from within serial_fpga.so.
    // We cache the routine address so we don't need to look it up every
    // time we want to send a packet.
    dlerror();                  /* Clear any existing error */
    *(void **) (&(pctx->sendrecv_pkt)) = dlsym(Slots[pctx->parent].handle, "sendrecv_pkt");
    errmsg = dlerror();         /* check for errors */
    if (errmsg != NULL) {
        return(-1);
    }

    return (0);
}


/**************************************************************
 * usercmd():  - The user is reading or setting a resource
 **************************************************************/
void usercmd(
    int       cmd,      //==EDGET if a read, ==EDSET on write
    int       rscid,    // ID of resource being accessed
    char     *val,      // new value for the resource
    SLOT     *pslot,    // pointer to slot info.
    int       cn,       // Index into UI table for requesting conn
    int      *plen,     // size of buf on input, #char in buf on output
    char     *buf)
{
    HBA_SERVO *pctx;     // hba_servo private info
    int       new_center=HBA_DEF_CENTER;     // new value for SERVO pins
    int       new_position=HBA_DEF_POSITION; // new direction for SERVO pins
    int       nsd;      // number of bytes sent to FPGA
    int       ret;      // generic call return value
    uint8_t   pkt[HBA_MXPKT];  

    // Get this instance of the plug-in
    pctx = (HBA_SERVO *) pslot->priv;


    if ((cmd == EDGET) && (rscid == RSC_CENTER)) {
        ret = snprintf(buf, *plen, "%x\n", pctx->center);
        *plen = ret;  // (errors are handled in calling routine)
    }
    else if ((cmd == EDGET) && (rscid == RSC_POSITION)) {
        ret = snprintf(buf, *plen, "%x\n", pctx->position);
        *plen = ret;  // (errors are handled in calling routine)
    }
    else if ((cmd == EDSET) && (rscid == RSC_CENTER)) {
        ret = sscanf(val, "%x", &new_center);
        if ((ret != 1) || (new_center < 0) || (new_center > 0xff)) {
            ret = snprintf(buf, *plen, E_BDVAL, pslot->rsc[rscid].name);
            *plen = ret;  // (errors are handled in calling routine)
            return;
        }
        // record the new data value 
        pctx->center = new_center;

        // Send new value to FPGA SERVO value register
        pkt[0] = HBA_WRITE_CMD | ((1 -1) << 4) | pctx->coreid;
        pkt[1] = HBA_SERVO_REG_CENTER;
        pkt[2] = pctx->center; // new value
        pkt[3] = 0;                             // dummy for the ack
        nsd = pctx->sendrecv_pkt(pctx->parent, 4, pkt);
        // We did a write so the sendrecv return value should be 1
        // and the returned byte should be an ACK
        if ((nsd != 1) || (pkt[0] != HBA_ACK)) {
            // error writing value from SERVO port
            ret = snprintf(buf, *plen, E_NORSP, pslot->rsc[rscid].name);
            *plen = ret;
        }
    }
    else if ((cmd == EDSET) && (rscid == RSC_POSITION)) {
        ret = sscanf(val, "%x", &new_position);
        if ((ret != 1) || (new_position < 0) || (new_position > 0xff)) {
            ret = snprintf(buf, *plen, E_BDVAL, pslot->rsc[rscid].name);
            *plen = ret;
            return;
        }
        // record the new data direction 
        pctx->position = new_position;

        // Send new direction to FPGA SERVO direction register
        pkt[0] = HBA_WRITE_CMD | ((1 -1) << 4) | pctx->coreid;
        pkt[1] = HBA_SERVO_REG_POSITION;
        pkt[2] = pctx->position; // new direction
        pkt[3] = 0;                             // dummy for the ack
        nsd = pctx->sendrecv_pkt(pctx->parent, 4, pkt);
        // We did a write so the sendrecv return value should be 1
        // and the returned byte should be an ACK
        if ((nsd != 1) || (pkt[0] != HBA_ACK)) {
            // error writing value from SERVO port
            ret = snprintf(buf, *plen, E_BDVAL, pslot->rsc[rscid].name);
            *plen = ret;
        }
    }
    // Nothing to do here if edcat.  That is handled in the UI code

    return;
}

// end of hba_servo.c
