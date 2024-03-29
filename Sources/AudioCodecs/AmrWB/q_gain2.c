/*--------------------------------------------------------------------------*
 *                         Q_GAIN2.C										*
 *--------------------------------------------------------------------------*
 * Quantization of pitch and codebook gains.                                *
 * MA prediction is performed on the innovation energy (in dB with mean     *
 * removed).                                                                *
 * An initial predicted gain, g_0, is first determined and the correction   *
 * factor     alpha = gain / g_0    is quantized.                           *
 * The pitch gain and the correction factor are vector quantized and the    *
 * mean-squared weighted error criterion is used in the quantizer search.   *
 *--------------------------------------------------------------------------*/

#include "typedef.h"
#include "basic_op.h"
#include "oper_32b.h"
#include "math_op.h"
#include "count.h"
#include "log2.h"

#include "acelp.h"

#include "q_gain2.tab"

#define MEAN_ENER    30
#define RANGE        64
#define PRED_ORDER   4


/* MA prediction coeff ={0.5, 0.4, 0.3, 0.2} in Q13 */
static Word16 pred[PRED_ORDER] = {4096, 3277, 2458, 1638};


void Init_Q_gain2(
     Word16 * mem                          /* output  :static memory (2 words)      */
)
{
    Word16 i;

    /* 4nd order quantizer energy predictor (init to -14.0 in Q10) */
    for (i = 0; i < PRED_ORDER; i++)
    {
        mem[i] = -14336;                   move16();  /* past_qua_en[i] */
    }

    return;
}


Word16 Q_gain2(                            /* Return index of quantization.          */
     Word16 xn[],                          /* (i) Q_xn: Target vector.               */
     Word16 y1[],                          /* (i) Q_xn: Adaptive codebook.           */
     Word16 Q_xn,                          /* (i)     : xn and y1 format             */
     Word16 y2[],                          /* (i) Q9  : Filtered innovative vector.  */
     Word16 code[],                        /* (i) Q9  : Innovative vector.           */
     Word16 g_coeff[],                     /* (i)     : Correlations <xn y1> <y1 y1> */
                                           /*           Compute in G_pitch().        */
     Word16 L_subfr,                       /* (i)     : Subframe lenght.             */
     Word16 nbits,                         /* (i)     : number of bits (6 or 7)      */
     Word16 * gain_pit,                    /* (i/o)Q14: Pitch gain.                  */
     Word32 * gain_cod,                    /* (o) Q16 : Code gain.                   */
     Word16 gp_clip,                       /* (i)     : Gp Clipping flag             */
     Word16 * mem                          /* (i/o)   : static memory (2 words)      */
)
{
    Word16 i, j, index, *p, min_ind, size;
    Word16 exp, frac, gcode0, exp_gcode0, e_max, exp_code, qua_ener;
    Word16 g_pitch, g2_pitch, g_code, g_pit_cod, g2_code, g2_code_lo;
    Word16 coeff[5], coeff_lo[5], exp_coeff[5];
    Word16 exp_max[5];
    Word32 L_tmp, dist_min;
    Word16 *past_qua_en, *t_qua_gain;

    past_qua_en = mem;                     move16();

    /*-----------------------------------------------------------------*
     * - Find the initial quantization pitch index                     *
     * - Set gains search range                                        *
     *-----------------------------------------------------------------*/
    test();
    if (sub(nbits, 6) == 0)
    {
        t_qua_gain = t_qua_gain6b;         move16();
        min_ind = 0;                       move16();
        size = RANGE;                      move16();

        test();
        if (sub(gp_clip, 1) == 0)
        {
            size = sub(size, 16);          /* limit gain pitch to 1.0 */
        }
    } else
    {
        t_qua_gain = t_qua_gain7b;         move16();

        p = t_qua_gain7b + RANGE;          move16();  /* pt at 1/4th of table */

        j = nb_qua_gain7b - RANGE;         move16();
        test();
        if (sub(gp_clip, 1) == 0)
        {
            j = sub(j, 27);                /* limit gain pitch to 1.0 */
        }
        min_ind = 0;                       move16();
        g_pitch = *gain_pit;               move16();

        for (i = 0; i < j; i++, p += 2)
        {
            test();
            if (sub(g_pitch, *p) > 0)
            {
                min_ind = add(min_ind, 1);
            }
        }
        size = RANGE;                      move16();
    }

    /*------------------------------------------------------------------*
     *  Compute coefficient need for the quantization.                  *
     *                                                                  *
     *  coeff[0] =    y1 y1                                             *
     *  coeff[1] = -2 xn y1                                             *
     *  coeff[2] =    y2 y2                                             *
     *  coeff[3] = -2 xn y2                                             *
     *  coeff[4] =  2 y1 y2                                             *
     *                                                                  *
     * Product <y1 y1> and <xn y1> have been compute in G_pitch() and   *
     * are in vector g_coeff[].                                         *
     *------------------------------------------------------------------*/

    coeff[0] = g_coeff[0];                 move16();
    exp_coeff[0] = g_coeff[1];             move16();
    coeff[1] = negate(g_coeff[2]);         move16();  /* coeff[1] = -2 xn y1 */
    exp_coeff[1] = add(g_coeff[3], 1);     move16();

    /* Compute scalar product <y2[],y2[]> */
    move16();move16();
    coeff[2] = extract_h(Dot_product12(y2, y2, L_subfr, &exp));
    exp_coeff[2] = add(sub(exp, 18), shl(Q_xn, 1));     /* -18 (y2 Q9) */

    /* Compute scalar product -2*<xn[],y2[]> */
    move16();move16();
    coeff[3] = extract_h(L_negate(Dot_product12(xn, y2, L_subfr, &exp)));
    exp_coeff[3] = add(sub(exp, 9 - 1), Q_xn);  /* -9 (y2 Q9), +1 (2 xn y2) */

    /* Compute scalar product 2*<y1[],y2[]> */
    move16();move16();
    coeff[4] = extract_h(Dot_product12(y1, y2, L_subfr, &exp));
    exp_coeff[4] = add(sub(exp, 9 - 1), Q_xn);  /* -9 (y2 Q9), +1 (2 y1 y2) */

    /*-----------------------------------------------------------------*
     *  Find energy of code and compute:                               *
     *                                                                 *
     *    L_tmp = MEAN_ENER - 10log10(energy of code/ L_subfr)         *
     *          = MEAN_ENER - 3.0103*log2(energy of code/ L_subfr)     *
     *-----------------------------------------------------------------*/

    L_tmp = Dot_product12(code, code, L_subfr, &exp_code);
    /* exp_code: -18 (code in Q9), -6 (/L_subfr), -31 (L_tmp Q31->Q0) */
    exp_code = sub(exp_code, 18 + 6 + 31);

    Log2(L_tmp, &exp, &frac);
    exp = add(exp, exp_code);
    L_tmp = Mpy_32_16(exp, frac, -24660);  /* x -3.0103(Q13) -> Q14 */

    L_tmp = L_mac(L_tmp, MEAN_ENER, 8192); /* + MEAN_ENER in Q14 */

    /*-----------------------------------------------------------------*
     * Compute gcode0.                                                 *
     *  = Sum(i=0,1) pred[i]*past_qua_en[i] + mean_ener - ener_code    *
     *-----------------------------------------------------------------*/

    L_tmp = L_shl(L_tmp, 10);              /* From Q14 to Q24 */
    L_tmp = L_mac(L_tmp, pred[0], past_qua_en[0]);      /* Q13*Q10 -> Q24 */
    L_tmp = L_mac(L_tmp, pred[1], past_qua_en[1]);      /* Q13*Q10 -> Q24 */
    L_tmp = L_mac(L_tmp, pred[2], past_qua_en[2]);      /* Q13*Q10 -> Q24 */
    L_tmp = L_mac(L_tmp, pred[3], past_qua_en[3]);      /* Q13*Q10 -> Q24 */

    gcode0 = extract_h(L_tmp);             /* From Q24 to Q8  */

    /*-----------------------------------------------------------------*
     * gcode0 = pow(10.0, gcode0/20)                                   *
     *        = pow(2, 3.321928*gcode0/20)                             *
     *        = pow(2, 0.166096*gcode0)                                *
     *-----------------------------------------------------------------*/

    L_tmp = L_mult(gcode0, 5443);          /* *0.166096 in Q15 -> Q24     */
    L_tmp = L_shr(L_tmp, 8);               /* From Q24 to Q16             */
    L_Extract(L_tmp, &exp_gcode0, &frac);  /* Extract exponent of gcode0  */

    gcode0 = extract_l(Pow2(14, frac));    /* Put 14 as exponent so that  */
    /* output of Pow2() will be:   */
    /* 16384 < Pow2() <= 32767     */
    exp_gcode0 = sub(exp_gcode0, 14);

    /*-------------------------------------------------------------------------*
     * Find the best quantizer                                                 *
     * ~~~~~~~~~~~~~~~~~~~~~~~                                                 *
     * Before doing the computation we need to aling exponents of coeff[]      *
     * to be sure to have the maximum precision.                               *
     *                                                                         *
     * In the table the pitch gains are in Q14, the code gains are in Q11 and  *
     * are multiply by gcode0 which have been multiply by 2^exp_gcode0.        *
     * Also when we compute g_pitch*g_pitch, g_code*g_code and g_pitch*g_code  *
     * we divide by 2^15.                                                      *
     * Considering all the scaling above we have:                              *
     *                                                                         *
     *   exp_code = exp_gcode0-11+15 = exp_gcode0+4                            *
     *                                                                         *
     *   g_pitch*g_pitch  = -14-14+15                                          *
     *   g_pitch          = -14                                                *
     *   g_code*g_code    = (2*exp_code)+15                                    *
     *   g_code           = exp_code                                           *
     *   g_pitch*g_code   = -14 + exp_code +15                                 *
     *                                                                         *
     *   g_pitch*g_pitch * coeff[0]  ;exp_max0 = exp_coeff[0] - 13             *
     *   g_pitch         * coeff[1]  ;exp_max1 = exp_coeff[1] - 14             *
     *   g_code*g_code   * coeff[2]  ;exp_max2 = exp_coeff[2] +15+(2*exp_code) *
     *   g_code          * coeff[3]  ;exp_max3 = exp_coeff[3] + exp_code       *
     *   g_pitch*g_code  * coeff[4]  ;exp_max4 = exp_coeff[4] + 1 + exp_code   *
     *-------------------------------------------------------------------------*/

    exp_code = add(exp_gcode0, 4);

    exp_max[0] = sub(exp_coeff[0], 13);    move16();
    exp_max[1] = sub(exp_coeff[1], 14);    move16();
    exp_max[2] = add(exp_coeff[2], add(15, shl(exp_code, 1)));  move16();
    exp_max[3] = add(exp_coeff[3], exp_code);   move16();
    exp_max[4] = add(exp_coeff[4], add(1, exp_code));   move16();

    /* Find maximum exponant */

    e_max = exp_max[0];                    move16();
    for (i = 1; i < 5; i++)
    {
        test();
        if (sub(exp_max[i], e_max) > 0)
        {
            e_max = exp_max[i];            move16();
        }
    }

    /* align coeff[] and save in special 32 bit double precision */

    for (i = 0; i < 5; i++)
    {
        j = add(sub(e_max, exp_max[i]), 2);/* /4 to avoid overflow */
        L_tmp = L_deposit_h(coeff[i]);
        L_tmp = L_shr(L_tmp, j);
        L_Extract(L_tmp, &coeff[i], &coeff_lo[i]);
        coeff_lo[i] = shr(coeff_lo[i], 3); move16();  /* lo >> 3 */
    }

    /* Codebook search */

    dist_min = MAX_32;                     move32();
    p = &t_qua_gain[shl(min_ind, 1)];      move16();

    index = 0;                             move16();
    for (i = 0; i < size; i++)
    {
        g_pitch = *p++;                    move16();
        g_code = *p++;                     move16();

        g_code = mult_r(g_code, gcode0);
        g2_pitch = mult_r(g_pitch, g_pitch);
        g_pit_cod = mult_r(g_code, g_pitch);
        L_tmp = L_mult(g_code, g_code);
        L_Extract(L_tmp, &g2_code, &g2_code_lo);

        L_tmp = L_mult(coeff[2], g2_code_lo);
        L_tmp = L_shr(L_tmp, 3);
        L_tmp = L_mac(L_tmp, coeff_lo[0], g2_pitch);
        L_tmp = L_mac(L_tmp, coeff_lo[1], g_pitch);
        L_tmp = L_mac(L_tmp, coeff_lo[2], g2_code);
        L_tmp = L_mac(L_tmp, coeff_lo[3], g_code);
        L_tmp = L_mac(L_tmp, coeff_lo[4], g_pit_cod);
        L_tmp = L_shr(L_tmp, 12);
        L_tmp = L_mac(L_tmp, coeff[0], g2_pitch);
        L_tmp = L_mac(L_tmp, coeff[1], g_pitch);
        L_tmp = L_mac(L_tmp, coeff[2], g2_code);
        L_tmp = L_mac(L_tmp, coeff[3], g_code);
        L_tmp = L_mac(L_tmp, coeff[4], g_pit_cod);

        test();
        if (L_sub(L_tmp, dist_min) < (Word32) 0)
        {
            dist_min = L_tmp;              move32();
            index = i;                     move16();
        }
    }

    /* Read the quantized gains */

    index = add(index, min_ind);

    p = &t_qua_gain[add(index, index)];    move16();
    *gain_pit = *p++;                      move16();  /* selected pitch gain in Q14 */
    g_code = *p++;                         move16();  /* selected code gain in Q11  */

    L_tmp = L_mult(g_code, gcode0);             /* Q11*Q0 -> Q12 */
    L_tmp = L_shl(L_tmp, add(exp_gcode0, 4));   /* Q12 -> Q16 */

    *gain_cod = L_tmp;                     move16();  /* gain of code in Q16 */

    /*---------------------------------------------------*
     * qua_ener = 20*log10(g_code)                       *
     *          = 6.0206*log2(g_code)                    *
     *          = 6.0206*(log2(g_codeQ11) - 11)          *
     *---------------------------------------------------*/

    L_tmp = L_deposit_l(g_code);
    Log2(L_tmp, &exp, &frac);
    exp = sub(exp, 11);
    L_tmp = Mpy_32_16(exp, frac, 24660);   /* x 6.0206 in Q12 */

    qua_ener = extract_l(L_shr(L_tmp, 3)); /* result in Q10 */

    /* update table of past quantized energies */

    past_qua_en[3] = past_qua_en[2];       move16();
    past_qua_en[2] = past_qua_en[1];       move16();
    past_qua_en[1] = past_qua_en[0];       move16();
    past_qua_en[0] = qua_ener;             move16();

    return (index);
}
