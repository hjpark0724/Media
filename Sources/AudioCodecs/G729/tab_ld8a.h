/*
   ITU-T G.729 Annex C - Reference C code for floating point
                         implementation of G.729 Annex A
                         Version 1.01 of 15.September.98
*/

/*
----------------------------------------------------------------------
                    COPYRIGHT NOTICE
----------------------------------------------------------------------
   ITU-T G.729 Annex C ANSI C source code
   Copyright (C) 1998, AT&T, France Telecom, NTT, University of
   Sherbrooke.  All rights reserved.

----------------------------------------------------------------------
*/

extern FFLOAT hamwindow[L_WINDOW];
extern FFLOAT lwindow[MP1];
extern FFLOAT lspcb1[NC0][M];
extern FFLOAT lspcb2[NC1][M];
extern FFLOAT fg[2][MA_NP][M];
extern FFLOAT fg_sum[2][M];
extern FFLOAT fg_sum_inv[2][M];
extern FFLOAT grid[GRID_POINTS+1];
extern FFLOAT inter_3l[FIR_SIZE_SYN];
extern FFLOAT pred[4];
extern FFLOAT gbk1[NCODE1][2];
extern FFLOAT gbk2[NCODE2][2];
extern int map1[NCODE1];
extern int map2[NCODE2];
extern FFLOAT coef[2][2];
extern FFLOAT thr1[NCODE1-NCAN1];
extern FFLOAT thr2[NCODE2-NCAN2];
extern int imap1[NCODE1];
extern int imap2[NCODE2];
extern FFLOAT b100[3];
extern FFLOAT a100[3];
extern FFLOAT b140[3];
extern FFLOAT a140[3];
extern int  bitsno[PRM_SIZE];
