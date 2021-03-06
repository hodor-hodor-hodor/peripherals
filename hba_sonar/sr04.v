/*
*****************************
* MODULE : sr04.v
*
* This module provides an interface to a SR04
* sonar module which has Trig and Echo pins.
* It outputs dist[7:0] which multiplied by 0.55
* give approximate distance in inches.
* This assumes the clk input is at 50mhz.
*
* Status: In development
*
* Author : Brandon Blodget
* Create Date: 06/08/2019
*
*****************************
*/

/*
*****************************
*
* Copyright (C) 2019 by Brandon Blodget <brandon.blodget@gmail.com>
* All rights reserved.
*
* License:
*
* This program is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
*
*****************************
*/

// Force error when implicit net has no type.
`default_nettype none

module sr04
(
    input wire clk,     // assume 50mhz
    input wire reset,
    input wire en,
    input wire sync,

    output reg trig,
    input wire echo,

    output reg [7:0] dist,  // actually time which is proportional to dist
    output reg valid        // new dist value
);

// Find posedge of sync
reg sync_reg;
wire posedge_sync;

assign posedge_sync = (sync==1) && (sync_reg==0);

always @ (posedge clk)
begin
    if (reset) begin
        sync_reg <= 0;
    end else begin
        sync_reg <= sync;
    end
end

// Generate the 10us trig pulse
// 10us / 20ns(50mhz) = 500
localparam TRIG_TIME = 500;
reg [8:0] trig_count;
reg trig_sent;
always @ (posedge clk)
begin
    if (reset) begin
        trig <= 0;
        trig_count <= 0;
        trig_sent <= 0;
    end else begin
        if (en) begin
            trig_sent <= 0;
            if (posedge_sync) begin
                trig <= 1;
            end
            if (trig) begin
                trig_count <= trig_count + 1;
                if (trig_count == TRIG_TIME) begin
                    trig <= 0;
                    trig_count <= 0;
                    trig_sent <= 1;
                end
            end
        end else begin
            // default values
            trig <= 0;
            trig_count <= 0;
            trig_sent <= 0;
        end
    end
end

// Find edges on echo signal
reg echo_reg;
wire echo_posedge;
wire echo_negedge;
assign echo_posedge = (echo==1) && (echo_reg==0);
assign echo_negedge = (echo==0) && (echo_reg==1);

always @ (posedge clk)
begin
    if (reset) begin
        echo_reg <= 0;
    end else begin
        echo_reg <= echo;
    end
end

// Time until echo
// dist(meters) = time(s) * 340(m/s) / 2 
// dist(inches) = time(s) * 13386(i/s) / 2 
// max distance =  10 feet = 120 inches
// max time = 120(inches)*2/13386 =~ .02 seconds
// 20-bit timer, 20ns(50mhz) * 2^20 = .021 seconds
// resolution = 0.5 inches
// time(0.5in) = 0.5(in)*2/13386 =~ 75us = 3750 clocks (50mhz) =~ 2^12
reg [19:0] echo_time;
reg timing;
reg wait_for_echo;
always @ (posedge clk)
begin
    if (reset) begin
        echo_time <= 0;
        timing <= 0;
        dist <= 0;
        valid <= 0;
        wait_for_echo <= 0;
    end else begin
        valid <= 0;

        // Triger has been sent start timer
        if (trig_sent) begin
            wait_for_echo <= 1;
        end 

        if (wait_for_echo) begin
            if (echo_posedge) begin
                timing <= 1;
                wait_for_echo <= 0;
            end
        end

        // Wait for echo or timeout
        if (timing) begin
            echo_time <= echo_time + 1;

            // Echo goes low.  Stop timer
            if (echo_negedge) begin
                // divide echo_time by 2^12 = 82us resoution 
                // = .55 inches resolution or
                // = 13.94 mm
                dist[7:0] <= echo_time[19:12];
                valid <= 1;
                timing <= 0;
                echo_time <= 0;
            end

            // No echo seen.  Handle timeout
            // Return max value.
            if (echo_time[19]) begin
                timing <= 0;
                echo_time <= 0;
                dist[7:0] <= 8'hff;
                valid <= 1;
            end

        end
    end
end

endmodule

