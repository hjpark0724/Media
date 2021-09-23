/*------------------------------------------------------------------------*
 *                         BITS.C                                         *
 *------------------------------------------------------------------------*
 * Performs bit stream manipulation                                       *
 *------------------------------------------------------------------------*/

#include <stdlib.h>
#include <stdio.h>
#include "typedef.h"
#include "basic_op.h"
#include "cnst.h"
#include "bits.h"
#include "acelp.h"
#include "count.h"
#include "dtx.h"

/*-----------------------------------------------------*
 * Write_serial -> write serial stream into a file     *
 *-----------------------------------------------------*/

Word16 Init_write_serial(TX_State ** st)
{
   TX_State *s;

   /* allocate memory */
    test();
    if ((s = (TX_State *) malloc(sizeof(TX_State))) == NULL)
    {
        fprintf(stderr, "write_serial_init: can not malloc state structure\n");
        return -1;
    }
    Reset_write_serial(s);
    *st = s;

    return 0;
}

Word16 Close_write_serial(TX_State *st)
{
   /* allocate memory */
    test();
    if (st != NULL)
    {
        free(st);
        st = NULL;
        return 0;
    }    
    return 1;
}

void Reset_write_serial(TX_State * st)
{
    st->sid_update_counter = 3;
    st->sid_handover_debt = 0;
    st->prev_ft = TX_SPEECH;
}

void Write_serial(FILE * fp, Word16 prms[], Word16 coding_mode, Word16 mode, TX_State *st)
{
   Word16 i, frame_type;
   Word16 stream[MAX_SIZE];
   
   if (coding_mode == MRDTX)
   {
      
      st->sid_update_counter--;
      
      if (st->prev_ft == TX_SPEECH)
      {
         frame_type = TX_SID_FIRST;
         st->sid_update_counter = 3;
      } else
      {
         if ((st->sid_handover_debt > 0) &&
            (st->sid_update_counter > 2))
         {
            /* ensure extra updates are  properly delayed after a possible SID_FIRST */
            frame_type = TX_SID_UPDATE;
            st->sid_handover_debt--;
         } else
         {
            if (st->sid_update_counter == 0)
            {
               frame_type = TX_SID_UPDATE;
               st->sid_update_counter = 8;
            } else
            {
               frame_type = TX_NO_DATA;
            }
         }
      }
   } else
   {
      st->sid_update_counter = 8;
      frame_type = TX_SPEECH;
   }
   st->prev_ft = frame_type;
   
   
   stream[0] = TX_FRAME_TYPE;
   stream[1] = frame_type;
   stream[2] = mode;
   for (i = 0; i < nb_of_bits[coding_mode]; i++)
   {
      stream[3 + i] = prms[i];
   }
   
   fwrite(stream, sizeof(Word16), 3 + nb_of_bits[coding_mode], fp);
   
   return;
}


/*-----------------------------------------------------*
 * Read_serial -> read serial stream into a file       *
 *-----------------------------------------------------*/

Word16 Read_serial(FILE * fp, Word16 prms[], Word16 * frame_type, Word16 * mode)
{
   Word16 n, type_of_frame_type, coding_mode;
   
   n = (Word16) fread(&type_of_frame_type, sizeof(Word16), 1, fp);
   n = (Word16) (n + fread(frame_type, sizeof(Word16), 1, fp));
   n = (Word16) (n + fread(mode, sizeof(Word16), 1, fp));
   coding_mode = *mode;
   if (n == 3)
   {
      if (type_of_frame_type == TX_FRAME_TYPE)
      {
         switch (*frame_type)
         {
         case TX_SPEECH:
            *frame_type = RX_SPEECH_GOOD;
            break;
         case TX_SID_FIRST:
            *frame_type = RX_SID_FIRST;
            break;
         case TX_SID_UPDATE:
            *frame_type = RX_SID_UPDATE;
            break;
         case TX_NO_DATA:
            *frame_type = RX_NO_DATA;
            break;
         }
      } else if (type_of_frame_type != RX_FRAME_TYPE)
      {
         fprintf(stderr, "Wrong type of frame type:%d.\n", type_of_frame_type);
      }
      
      if ((*frame_type == RX_SID_FIRST) | (*frame_type == RX_SID_UPDATE) | (*frame_type == RX_NO_DATA) | (*frame_type == RX_SID_BAD))
      {
         coding_mode = MRDTX;
      }
      n = (Word16) fread(prms, sizeof(Word16), nb_of_bits[coding_mode], fp);
      if (n != nb_of_bits[coding_mode])
         n = 0;
   }
   return (n);
}


/*-----------------------------------------------------*
 * Parm_serial -> convert parameters to serial stream  *
 *-----------------------------------------------------*/

void Parm_serial(
     Word16 value,                         /* input : parameter value */
     Word16 no_of_bits,                    /* input : number of bits  */
     Word16 ** prms
)
{
    Word16 i, bit;

    *prms += no_of_bits;                   move16();

    for (i = 0; i < no_of_bits; i++)
    {
        bit = (Word16) (value & 0x0001);   logic16();  /* get lsb */
        test();move16();
        if (bit == 0)
            *--(*prms) = BIT_0;
        else
            *--(*prms) = BIT_1;
        value = shr(value, 1);             move16();
    }
    *prms += no_of_bits;                   move16();
    return;
}


/*----------------------------------------------------*
 * Serial_parm -> convert serial stream to parameters *
 *----------------------------------------------------*/

Word16 Serial_parm(                        /* Return the parameter    */
     Word16 no_of_bits,                    /* input : number of bits  */
     Word16 ** prms
)
{
    Word16 value, i;
    Word16 bit;

    value = 0;                             move16();
    for (i = 0; i < no_of_bits; i++)
    {
        value = shl(value, 1);
        bit = *((*prms)++);                move16();
        test();move16();
        if (bit == BIT_1)
            value = add(value, 1);
    }
    return (value);
}
