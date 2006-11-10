/*

MBID.c v1.0

LICENSE

Copyright (c) 2006, David Nicolson
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:

  1. Redistributions of source code must retain the above copyright
     notice, this list of conditions and the following disclaimer.
  2. Redistributions in binary form must reproduce the above copyright
     notice, this list of conditions and the following disclaimer in the
     documentation and/or other materials provided with the distribution.
  3. Neither the name of the author nor the names of its contributors
     may be used to endorse or promote products derived from this software
     without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT UNLESS REQUIRED BY
LAW OR AGREED TO IN WRITING WILL ANY COPYRIGHT HOLDER OR CONTRIBUTOR
BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY,
OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, PROFITS; OR
BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#ifndef __NT__
#include <sys/errno.h>
#endif

#include "MBID.h"

#ifdef MBID_DEBUG
#define debug(fmt, ...) printf(fmt, ## __VA_ARGS__)
#else
#define debug(fmt, ...)
#endif


int toSynchSafe32(char bytes[]) {
    return ((int)bytes[0] << 21) + ((int)bytes[1] << 14) + ((int)bytes[2] << 7) + (int)bytes[3];
}

int toInteger32(char bytes[]) {
    int size = 0;
    int i;
    for (i=0; i<4; i++) {
        size = size * 256 + ((int)bytes[i] & 0x000000FF);
    }
    return size;
}

int mfile(int length, char ret[], FILE *fp) {
    int bytes = fread(ret,1,length,fp);
    
    if (bytes == length) {
        return 0;
    } else {
        return -1;
    }
}
    
int getMBID(const char *path, char mbid[MBID_BUFFER_SIZE]) {

    FILE *fp;
    int s = 1;
    char head[3];
    char version[2];
    char flag[1];
    char size[4];
    char size_extended[4];
    int tag_size = 0;
    int extended_size = 0;
    char frame_bytes[4];
    char frame_header[4];
    int frame_size = 0;

    if (path == NULL) {
        debug("Received null path");
        errno = EINVAL;
        return -1;
    }

    fp = fopen(path,"rb");
    if (fp == NULL) {
        debug("Could not open file: %s\n",path);
        return -1;
    }

    while (s) {
        if (-1 == mfile(3,head,fp)) break;

        if (!strncmp(head,"ID3",3) == 0) {
            debug("No ID3v2 tag found: %s\n",path);
            errno = EINVAL;
            goto mbid_err_exit;
        }

        if (-1 == mfile(2,version,fp)) break;
        int version_major = (int)version[0];
        if (version_major == 2) {
            debug("ID3v2.2.0 does not support MBIDs: %s\n",path);
            errno = EINVAL;
            goto mbid_err_exit;
        }
        if (version_major != 3 && version_major != 4) {
            debug("Unsupported ID3 version: %d",version_major);
            errno = EINVAL;
            goto mbid_err_exit;
        }

        if (-1 == mfile(1,flag,fp)) break;
        if ((unsigned int)flag[0] & 0x00000040) {
            debug("Extended header found.\n");
            if (version[0] == 4) {
                if (-1 == mfile(4,size_extended,fp)) break;
                extended_size = toSynchSafe32(size_extended);
            } else {
                if (-1 == mfile(4,size_extended,fp)) break;
                extended_size = toInteger32(size_extended);
            }
            debug("Extended header size: %d\n",extended_size);
            fseek(fp,extended_size,SEEK_CUR);
        }
    
        if (-1 == mfile(4,size,fp)) break;
        tag_size = toSynchSafe32(size);
        debug("Tag size: %d\n",tag_size);

        while (1) {
            if (ftell(fp) > tag_size || ftell(fp) > 1048576) {
                errno = EFBIG;
                goto mbid_err_exit;
            }
            if (-1 == mfile(4,frame_bytes,fp)) goto mbid_err_exit; // frame ID

            if (frame_bytes[0] == 0x00) {
                errno = EINVAL;
                goto mbid_err_exit;
            }
            if (version_major == 4) {
                if (-1 == mfile(4,frame_header,fp)) goto mbid_err_exit;
                frame_size = toSynchSafe32(frame_header);
            } else {
                if (-1 == mfile(4,frame_header,fp)) goto mbid_err_exit;
                frame_size = toInteger32(frame_header);
            }
            if (frame_size <= 0 || frame_size >= tag_size) {
                debug("Bad frame size %d\n",frame_size);
                goto mbid_err_exit;
            }
   
            fseek(fp,2,SEEK_CUR); // 2 flag bytes
            debug("Reading %d bytes from %s\n",frame_size,frame_bytes);

            // Frame size check keeps us from blowing the stack
            if (strncmp(frame_bytes,"UFID", 4) == 0 && frame_size <= 1024) {
                char frame_data[frame_size];
                if (-1 ==  mfile(frame_size,frame_data,fp)) goto mbid_err_exit;
                if (frame_size >= 59 && strncmp(frame_data,"http://musicbrainz.org",22) == 0) {
                    char *tmbid = frame_data;
                    tmbid = frame_data + 23;
                    strncpy(mbid,tmbid,MBID_BUFFER_SIZE-1);
                    mbid[MBID_BUFFER_SIZE-1] = 0x00;
                    fclose(fp);
                    return 0;
                }
            }
            
            fseek(fp,frame_size,SEEK_CUR);
        }
    }
    
mbid_err_exit:
    if (fp)
        fclose(fp);
    debug("MBID not found: %s\n",path);
    return -1;

}

#ifdef MBID_DEBUG
int main(int argc, const char *argv[]) {

    char mbid[MBID_BUFFER_SIZE];

    if (getMBID(argv[1],mbid) == 0) {
        debug("File: %s\nMBID: %s\n\n", argv[1], mbid);
    }

}
#endif
