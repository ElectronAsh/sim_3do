/*
  www.freedo.org
  The first working 3DO multiplayer emulator.

  The FreeDO licensed under modified GNU LGPL, with following notes:

  *   The owners and original authors of the FreeDO have full right to
  *   develop closed source derivative work.

  *   Any non-commercial uses of the FreeDO sources or any knowledge
  *   obtained by studying or reverse engineering of the sources, or
  *   any other material published by FreeDO have to be accompanied
  *   with full credits.

  *   Any commercial uses of FreeDO sources or any knowledge obtained
  *   by studying or reverse engineering of the sources, or any other
  *   material published by FreeDO is strictly forbidden without
  *   owners approval.

  The above notes are taking precedence over GNU LGPL in conflicting
  situations.

  Project authors:
  *  Alexander Troosh
  *  Maxim Grishin
  *  Allen Wright
  *  John Sammons
  *  Felix Lazarev
*/

#include "opera_arm.h"
#include "opera_clio.h"
#include "opera_clock.h"
#include "opera_dsp.h"
#include "opera_madam.h"
#include "opera_xbus.h"

#include <string.h>

#define DECREMENT    0x1
#define RELOAD       0x2
#define CASCADE      0x4
#define FLABLODE     0x8
#define RELOAD_VAL   0x10

extern int fastrand(void);

struct fifo_s
{
  uint32_t addr;
  int32_t  len;
};

typedef struct fifo_s fifo_t;

struct clio_fifo_s
{
  int32_t idx;
  fifo_t  start;
  fifo_t  next;
};

typedef struct clio_fifo_s clio_fifo_t;

struct clio_s
{
  uint32_t    regs[65536];
  int32_t     dsp_word1;
  int32_t     dsp_word2;
  int32_t     dsp_address;
  clio_fifo_t fifo_i[13];
  clio_fifo_t fifo_o[4];
};

typedef struct clio_s clio_t;

int flagtime;
int TIMER_VAL = 0; //0x415

static uint32_t *MADAM_REGS;
static clio_t    CLIO;

uint32_t
opera_clio_state_size(void)
{
  return sizeof(clio_t);
}

void
opera_clio_state_save(void *buf_)
{
  memcpy(buf_,&CLIO,sizeof(clio_t));
}

void
opera_clio_state_load(const void *buf_)
{
  TIMER_VAL = 0;

  memcpy(&CLIO,buf_,sizeof(clio_t));
}

#define CURADR MADAM_REGS[base+0x00]
#define CURLEN MADAM_REGS[base+0x04]
#define RLDADR MADAM_REGS[base+0x08]
#define RLDLEN MADAM_REGS[base+0x0C]

void
opera_clio_timer_set(uint32_t v200_,
                     uint32_t v208_)
{
  (void) v200_;
  (void) v208_;
}

void
opera_clio_timer_clear(uint32_t v204_,
                       uint32_t v20C_)
{
  (void) v204_;
  (void) v20C_;
}

uint32_t
opera_clio_line_vint0(void)
{
  return (CLIO.regs[8] & 0x7FF);
}

uint32_t
opera_clio_line_vint1(void)
{
  return (CLIO.regs[12] & 0x7FF);
}

int
opera_clio_fiq_needed(void)
{
  return ((CLIO.regs[0x40] & CLIO.regs[0x48]) ||
          (CLIO.regs[0x60] & CLIO.regs[0x68]));
}

void
opera_clio_fiq_generate(uint32_t reason1_,
                        uint32_t reason2_)
{
  CLIO.regs[0x40] |= reason1_;
  CLIO.regs[0x60] |= reason2_;
  /* irq31 if exist irq32 and high */
  if (CLIO.regs[0x60]) CLIO.regs[0x40] |= 0x80000000;
}

static
void
clio_handle_dma(uint32_t val_)
{
  CLIO.regs[0x304] |= val_;

  if(val_ & 0x00100000)
    {
      int len;
      unsigned trg;
      uint8_t b0,b1,b2,b3;

      trg = opera_madam_peek(0x540);
      len = opera_madam_peek(0x544);
      CLIO.regs[0x304] &= ~0x00100000;
      CLIO.regs[0x400] &= ~0x80;

      if(CLIO.regs[0x404] & 0x200)
        {
          while(len >= 0)
            {
              b3 = opera_xbus_fifo_get_data();
              b2 = opera_xbus_fifo_get_data();
              b1 = opera_xbus_fifo_get_data();
              b0 = opera_xbus_fifo_get_data();

#ifdef MSB_FIRST
              opera_mem_write8(trg+0,b3);
              opera_mem_write8(trg+1,b2);
              opera_mem_write8(trg+2,b1);
              opera_mem_write8(trg+3,b0);
#else
              opera_mem_write8(trg+0,b0);
              opera_mem_write8(trg+1,b1);
              opera_mem_write8(trg+2,b2);
              opera_mem_write8(trg+3,b3);
#endif

              trg += 4;
              len -= 4;
            }

          CLIO.regs[0x400] |= 0x80;
        }
      else
        {
          while(len >= 0)
            {
              b3 = opera_xbus_fifo_get_data();
              b2 = opera_xbus_fifo_get_data();
              b1 = opera_xbus_fifo_get_data();
              b0 = opera_xbus_fifo_get_data();

#ifdef MSB_FIRST
              opera_mem_write8(trg+0,b3);
              opera_mem_write8(trg+1,b2);
              opera_mem_write8(trg+2,b1);
              opera_mem_write8(trg+3,b0);
#else
              opera_mem_write8(trg+0,b0);
              opera_mem_write8(trg+1,b1);
              opera_mem_write8(trg+2,b2);
              opera_mem_write8(trg+3,b3);
#endif

              trg += 4;
              len -= 4;
            }

          CLIO.regs[0x400] |= 0x80;
        }

      opera_madam_poke(0x544,0xFFFFFFFC);
      opera_clio_fiq_generate(1<<29,0);
    }
}

static
void
if_set_set_reset(uint32_t *output_,
                 uint32_t  val_,
                 uint32_t  mask_chk_,
                 uint32_t  mask_set_)
{
  if((val_ & mask_chk_) == mask_chk_)
    {
      *output_ = ((val_ & mask_set_) ?
                  (*output_ |  mask_set_) :
                  (*output_ & ~mask_set_));
    }
}

int
opera_clio_poke(uint32_t addr_,
                uint32_t val_)
{
  int base;
  int i;

  if(!flagtime)
    TIMER_VAL = 0;

  /* 0x40..0x4C, 0x60..0x6C case */
  if((addr_ & ~0x2C) == 0x40)
    {
      if(addr_ == 0x40)
        {
          CLIO.regs[0x40] |= val_;
          if(CLIO.regs[0x60]) CLIO.regs[0x40] |= 0x80000000;
          /*
            if(CLIO.regs[0x40]&CLIO.regs[0x48])
            _arm_SetFIQ();
          */
          return 0;
        }
      else if(addr_ == 0x44)
        {
          CLIO.regs[0x40] &= ~val_;
          if(!CLIO.regs[0x60]) CLIO.regs[0x40] &= ~0x80000000;
          return 0;
        }
      else if(addr_ == 0x48)
        {
          CLIO.regs[0x48] |= val_;
          /*
            if(CLIO.regs[0x40] & CLIO.regs[0x48])
            _arm_SetFIQ();
          */
          return 0;
        }
      else if(addr_ == 0x4C)
        {
          /* always one for irq31 */
          CLIO.regs[0x48] &= ~val_;
          CLIO.regs[0x48] |= 0x80000000;
          return 0;
        }
#if 0
      else if(addr_ == 0x50)
        {
          CLIO.regs[0x50] |= (val_ & 0x3FFF0000);
          return 0;
        }
      else if(addr_ == 0x54)
        {
          CLIO.regs[0x50] &= ~val;
          return 0;
        }
#endif
      else if(addr_ == 0x60)
        {
          CLIO.regs[0x60] |= val_;
          if(CLIO.regs[0x60]) CLIO.regs[0x40] |= 0x80000000;
          /*
            if(CLIO.regs[0x60] & CLIO.regs[0x68])
            _arm_SetFIQ();
          */
          return 0;
        }
      else if(addr_ == 0x64)
        {
          CLIO.regs[0x60] &= ~val_;
          if(!CLIO.regs[0x60]) CLIO.regs[0x40] &= ~0x80000000;
          return 0;
        }
      else if(addr_ == 0x68)
        {
          CLIO.regs[0x68] |= val_;
          /*
            if(CLIO.regs[0x60] & CLIO.regs[0x68])
            _arm_SetFIQ();
          */
          return 0;
        }
      else if(addr_ == 0x6C)
        {
          CLIO.regs[0x68] &= ~val_;
          return 0;
        }
    }
  else if(addr_ == 0x84)
    {
      if_set_set_reset(&CLIO.regs[0x84],val_,0x10,0x01);
      if_set_set_reset(&CLIO.regs[0x84],val_,0x20,0x02);
      if_set_set_reset(&CLIO.regs[0x84],val_,0x40,0x04);
      if_set_set_reset(&CLIO.regs[0x84],val_,0x80,0x08);

      opera_arm_rom_select( (val_ & 0x4) );

      return 0;
    }
  else if(addr_ == 0x0300)
    {
      /* clear down the fifos and stop them */
      base = 0;
      CLIO.regs[0x304] &= ~val_;

      for(i = 0; i < 13; i++)
        {
          if(val_ & (1 << i))
            {
              base = (0x400 + (i << 4));
              RLDADR = CURADR = 0;
              RLDLEN = CURLEN = 0;
              opera_clio_fifo_write(base + 0x00,0);
              opera_clio_fifo_write(base + 0x04,0);
              opera_clio_fifo_write(base + 0x08,0);
              opera_clio_fifo_write(base + 0x0C,0);
              val_ &= ~(1 << i);
              CLIO.fifo_i[i].idx = 0;
            }
        }

      for(i = 0; i < 4; i++)
        {
          if(val_ & (1 << (i + 16)))
            {
              base = (0x500 + (i << 4));
              RLDADR = CURADR = 0;
              RLDLEN = CURLEN = 0;
              opera_clio_fifo_write(base + 0x00,0);
              opera_clio_fifo_write(base + 0x04,0);
              opera_clio_fifo_write(base + 0x08,0);
              opera_clio_fifo_write(base + 0x0C,0);
              val_ &= ~(1 << (i + 16));
              CLIO.fifo_o[i].idx = 0;
            }
        }

      return 0;
    }
  else if(addr_ == 0x304) /* DMA starter */
    {
      clio_handle_dma(val_);
      switch(val_)
        {
        case 0x100000:
          if(TIMER_VAL < 5800)
            TIMER_VAL += 0x33;
          flagtime = (opera_clock_cpu_get_freq() / 2000000);
          break;
        default:
          if(!CLIO.regs[0x304])
            TIMER_VAL = 0;
          break;
        }
      return 0;
    }
  else if(addr_ == 0x308) /* DMA stopper */
    {
      CLIO.regs[0x304] &= ~val_;
      return 0;
    }
  else if(addr_ == 0x400) /* XBUS direction */
    {
      if(val_ & 0x800)
        return 0;

      CLIO.regs[0x400] = val_;
      return 0;
    }
  else if((addr_ >= 0x500) && (addr_ < 0x540))
    {
      opera_xbus_set_sel(val_);
      return 0;
    }
  else if((addr_ >= 0x540) && (addr_ < 0x580))
    {
      opera_xbus_set_poll(val_);
      return 0;
    }
  else if((addr_ >= 0x580) && (addr_ < 0x5C0))
    {
      /* on FIFO Filled execute the command */
      opera_xbus_fifo_set_cmd(val_);
      return 0;
    }
  else if((addr_ >= 0x5c0) && (addr_ < 0x600))
    {
      /* on FIFO Filled execute the command */
      opera_xbus_fifo_set_data(val_);
      return 0;
    }
  else if(addr_ == 0x28)
    {
      CLIO.regs[addr_] = val_;
      return (val_ == 0x30);
    }
  else if((addr_ >= 0x1800) && (addr_ <= 0x1FFF))
    {
      addr_ &= ~0x400; /* mirrors */
      CLIO.dsp_word1   = (val_ >> 16);
      CLIO.dsp_word2   = (val_ & 0xFFFF);
      CLIO.dsp_address = ((addr_ - 0x1800) >> 1);
      opera_dsp_mem_write(CLIO.dsp_address+0,CLIO.dsp_word1);
      opera_dsp_mem_write(CLIO.dsp_address+1,CLIO.dsp_word2);
      return 0;
      /* DSPNRAMWrite 2 DSPW per 1ARMW */
    }
  else if((addr_ >= 0x2000) && (addr_ <= 0x2FFF))
    {
      addr_ &= ~0x800; /* mirrors */
      CLIO.dsp_word1   = (val_ & 0xFFFF);
      CLIO.dsp_address = ((addr_ - 0x2000) >> 2);
      opera_dsp_mem_write(CLIO.dsp_address,CLIO.dsp_word1);
      return 0;
    }
  else if((addr_ >= 0x3000) && (addr_ <= 0x33FF))
    {
      CLIO.dsp_address  = ((addr_ - 0x3000) >> 1);
      CLIO.dsp_address &= 0xFF;
      CLIO.dsp_word1    = (val_ >> 16);
      CLIO.dsp_word2    = (val_ & 0xFFFF);
      opera_dsp_imem_write(CLIO.dsp_address+0,CLIO.dsp_word1);
      opera_dsp_imem_write(CLIO.dsp_address+1,CLIO.dsp_word2);
      return 0;
    }
  else if((addr_ >= 0x3400) && (addr_ <= 0x37FF))
    {
      CLIO.dsp_address  = ((addr_ - 0x3400) >> 2);
      CLIO.dsp_address &= 0xFF;
      CLIO.dsp_word1    = (val_ & 0xFFFF);
      opera_dsp_imem_write(CLIO.dsp_address,CLIO.dsp_word1);
      return 0;
    }
  else if(addr_ == 0x17E8) /* Reset */
    {
      opera_dsp_reset();
      return 0;
    }
  else if(addr_ == 0x17D0) /* Write DSP/ARM Semaphore */
    {
      opera_dsp_arm_semaphore_write(val_);
      return 0;
    }
  else if(addr_ == 0x17FC) /* start / stop */
    {
      opera_dsp_set_running(val_ > 0);
      return 0;
    }
  else if(addr_ == 0x200)
    {
      CLIO.regs[0x200] |= val_;
      opera_clio_timer_set(val_,0);
      return 0;
    }
  else if(addr_ == 0x204)
    {
      CLIO.regs[0x200] &= ~val_;
      opera_clio_timer_clear(val_,0);
      return 0;
    }
  else if(addr_ == 0x208)
    {
      CLIO.regs[0x208] |= val_;
      opera_clio_timer_set(0,val_);
      return 0;
    }
  else if(addr_ == 0x20C)
    {
      CLIO.regs[0x208] &= ~val_;
      opera_clio_timer_clear(0,val_);
      return 0;
    }
  else if(addr_ == 0x220)
    {
      CLIO.regs[addr_] = (val_ & 0x3FF);
      opera_clock_timer_set_delay(CLIO.regs[addr_]);
      return 0;
    }
  else if(addr_ == 0x120)
    {
      /* 316 or 800? */
      CLIO.regs[addr_] = ((TIMER_VAL > 800) ?
                          (TIMER_VAL+(val_/0x30)) : val_);
      return 0;
    }

  CLIO.regs[addr_] = val_;

  return 0;
}

uint32_t
opera_clio_peek(uint32_t addr_)
{
  /* 0x40..0x4C, 0x60..0x6C case */
  if((addr_ & ~0x2C) == 0x40)
    {
      /* By read 40 and 44, 48 and 4c, 60 and 64, 68 and 6c same */
      addr_ &= ~4;
      if(addr_ == 0x40)
        return CLIO.regs[0x40];
      else if(addr_ == 0x48)
        return (CLIO.regs[0x48] | 0x80000000);
      else if(addr_ == 0x60)
        return CLIO.regs[0x60];
      else if(addr_ == 0x68)
        return CLIO.regs[0x68];
      return 0;
    }
  else if(addr_ == 0x204)
    return CLIO.regs[0x200];
  else if(addr_ == 0x20C)
    return CLIO.regs[0x208];
  else if(addr_ == 0x308)
    return CLIO.regs[0x304];
  else if (addr_ == 0x414)
    return 0x4000; /* TO CHECK!!! requested by CDROMDIPIR */
  else if((addr_ >= 0x500) && (addr_ < 0x540))
    return opera_xbus_get_res();
  else if((addr_ >= 0x540) && (addr_ < 0x580))
    return opera_xbus_get_poll();
  else if((addr_ >= 0x580) && (addr_ < 0x5C0))
    return opera_xbus_fifo_get_status();
  else if((addr_ >= 0x5C0) && (addr_ < 0x600))
    return opera_xbus_fifo_get_data();
  else if(addr_ == 0x0)
    return 0x02020000;
  else if((addr_ >= 0x3800) && (addr_ <= 0x3BFF))
    {
      /* 2DSPW per 1ARMW */
      CLIO.dsp_address  = ((addr_ - 0x3800) >> 1);
      CLIO.dsp_address &= 0xFF;
      CLIO.dsp_address += 0x300;
      CLIO.dsp_word1    = opera_dsp_imem_read(CLIO.dsp_address+0);
      CLIO.dsp_word2    = opera_dsp_imem_read(CLIO.dsp_address+1);
      return ((CLIO.dsp_word1 << 16) | CLIO.dsp_word2);
    }
  else if((addr_ >= 0x3C00) && (addr_ <= 0x3FFF))
    {
      CLIO.dsp_address  = ((addr_ - 0x3C00) >> 2);
      CLIO.dsp_address &= 0xFF;
      CLIO.dsp_address += 0x300;
      return opera_dsp_imem_read(CLIO.dsp_address);
    }
  else if(addr_ == 0x17F0)
    return fastrand();
  else if(addr_ == 0x17D0) /* read DSP/ARM semaphore */
    return opera_dsp_arm_semaphore_read();

  return CLIO.regs[addr_];
}

void
opera_clio_vcnt_update(int line_,
                       int field_)
{
  CLIO.regs[0x34] = ((field_ << 11) + line_);
}

static
uint32_t
timer_flags(const uint32_t timer_)
{
  return ((CLIO.regs[((timer_ < 8) ? 0x200 : 0x208)] >> ((timer_ << 2) & 0x1F)) & 0xF);
}

static
void
timer_disable(const uint32_t timer_)
{
  CLIO.regs[((timer_ < 8) ? 0x200 : 0x208)] &= ~(DECREMENT << ((timer_ << 2)));
}

void
opera_clio_timer_execute(void)
{
  uint32_t *reg;
  uint32_t  flags;
  uint32_t  timer;
  uint32_t  carry;

  carry = 1;
  for(timer = 0; timer < 0x10; timer++)
    {
      flags = timer_flags(timer);
      if(!(flags & DECREMENT))
        continue;

      reg = &CLIO.regs[(0x100 + (timer << 3))];
      reg[0] -= ((flags & CASCADE) ? carry : 1);
      if(reg[0] == 0xFFFFFFFF)
        {
          carry = 1;
          if(timer & 1)
            opera_clio_fiq_generate(1<<(10-(timer>>1)),0);
          if(flags & RELOAD)
            reg[0] = reg[4];
          else
            timer_disable(timer);
        }
      else
        {
          carry = 0;
        }
    }
}

uint32_t
opera_clio_timer_get_delay(void)
{
  return CLIO.regs[0x220];
}

void opera_clio_init(int reason_)
{
  unsigned i;
  for(i = 0; i < 32768; i++)
    CLIO.regs[i] = 0;

  //CLIO.regs[8]=240;

  CLIO.regs[0x0028] = reason_;      // cstatbits
  CLIO.regs[0x0400] = 0x80;
  CLIO.regs[0x0220] = 64;
  MADAM_REGS = opera_madam_registers();
  TIMER_VAL  = 0;
}

void
opera_clio_reset(void)
{
  int i;

  for(i = 0;i < 65536; i++)
    CLIO.regs[i] = 0;
}

uint16_t
opera_clio_fifo_ei_read(uint16_t channel_)
{
#ifdef MSB_FIRST
  return opera_mem_read16(((CLIO.fifo_i[channel_].start.addr + CLIO.fifo_i[channel_].idx)));
#else
  return opera_mem_read16(((CLIO.fifo_i[channel_].start.addr + CLIO.fifo_i[channel_].idx)^2));
#endif
}

static
void
opera_clio_fifo_eo_write(uint16_t channel_,
                         uint16_t val_)
{
#ifdef MSB_FIRST
  opera_mem_write16(((CLIO.fifo_o[channel_].start.addr + CLIO.fifo_o[channel_].idx)),val_);
#else
  opera_mem_write16(((CLIO.fifo_o[channel_].start.addr + CLIO.fifo_o[channel_].idx)^2),val_);
#endif
}

uint16_t
opera_clio_fifo_ei(uint16_t channel_)
{
  if(CLIO.fifo_i[channel_].start.addr != 0) /* channel enabled */
    {
      uint32_t val_;

      if((CLIO.fifo_i[channel_].start.len - CLIO.fifo_i[channel_].idx) > 0)
        {
          val_ = opera_clio_fifo_ei_read(channel_);
          CLIO.fifo_i[channel_].idx += 2;
        }
      else
        {
          CLIO.fifo_i[channel_].idx = 0;
          opera_clio_fiq_generate(1<<(channel_+16),0);

          /* reload enabled see patent WO09410641A1, 49.16 */
          if(CLIO.fifo_i[channel_].next.addr != 0)
            {
              CLIO.fifo_i[channel_].start.addr = CLIO.fifo_i[channel_].next.addr;
              CLIO.fifo_i[channel_].start.len  = CLIO.fifo_i[channel_].next.len;

              val_ = opera_clio_fifo_ei_read(channel_);

              CLIO.fifo_i[channel_].idx += 2;
            }
          else
            {
              CLIO.fifo_i[channel_].start.addr = 0;
              val_ = 0;
            }
        }

      return val_;
    }

  // JMK SEZ: What is this? It was commented out along with this whole "else"
  //          block, but I had to bring this else block back from the dead
  //          in order to initialize val appropriately.

  // opera_clio_fiq_generate(1<<(channel_+16),0);
  return 0;
}

void
opera_clio_fifo_eo(uint16_t channel_,
                   uint16_t val_)
{
  /* Channel disabled? */
  if(CLIO.fifo_o[channel_].start.addr == 0)
    return;

  if((CLIO.fifo_o[channel_].start.len - CLIO.fifo_o[channel_].idx) > 0)
    {
      opera_clio_fifo_eo_write(channel_,val_);
      CLIO.fifo_o[channel_].idx += 2;
    }
  else
    {
      CLIO.fifo_o[channel_].idx = 0;
      opera_clio_fiq_generate(1<<(channel_+12),0);

      /* reload enabled? */
      if(CLIO.fifo_o[channel_].next.addr != 0)
        {
          CLIO.fifo_o[channel_].start.addr = CLIO.fifo_o[channel_].next.addr;
          CLIO.fifo_o[channel_].start.len  = CLIO.fifo_o[channel_].next.len;
        }
      else
        {
          CLIO.fifo_o[channel_].start.addr = 0;
        }
    }
}

uint16_t
opera_clio_fifo_ei_status(uint8_t channel_)
{
  if(CLIO.fifo_i[channel_].start.addr != 0)
    return 2; /* fixme */

  return 0;
}

uint16_t
opera_clio_fifo_eo_status(uint8_t channel_)
{
  if(CLIO.fifo_o[channel_].start.addr != 0)
    return 1;
  return 0;
}

uint32_t
opera_clio_fifo_read(uint32_t addr_)
{
  if((addr_ & 0x500) == 0x400)
    {
      switch(addr_ & 0x0F)
        {
        case 0x00:
          return CLIO.fifo_i[(addr_>>4) & 0xF].start.addr + CLIO.fifo_i[(addr_>>4)&0xF].idx;
        case 0x04:
          return CLIO.fifo_i[(addr_>>4) & 0xF].start.len - CLIO.fifo_i[(addr_>>4)&0xF].idx;
        case 0x08:
          return CLIO.fifo_i[(addr_>>4) & 0xF].next.addr;
        case 0x0C:
          return CLIO.fifo_i[(addr_>>4) & 0xF].next.len;
        }
    }

  switch(addr_ & 0xF)
    {
    case 0x00:
      return CLIO.fifo_o[(addr_>>4)&0xF].start.addr + CLIO.fifo_o[(addr_>>4)&0xF].idx;
    case 0x04:
      return CLIO.fifo_o[(addr_>>4)&0xF].start.len - CLIO.fifo_o[(addr_>>4)&0xF].idx;
    case 0x08:
      return CLIO.fifo_o[(addr_>>4)&0xF].next.addr;
    case 0x0C:
      return CLIO.fifo_o[(addr_>>4)&0xF].next.len;
    }

  return 0;
}

void
opera_clio_fifo_write(uint32_t addr_, uint32_t val_)
{
  if((addr_& 0x500) == 0x400)
    {
      switch(addr_ & 0x0F)
        {
        case 0x00:
          /* see patent WO09410641A1, 46.25 */
          CLIO.fifo_i[(addr_>>4)&0xF].start.addr = val_;
          CLIO.fifo_i[(addr_>>4)&0xF].next.addr  = 0;
          break;
        case 0x04:
          CLIO.fifo_i[(addr_>>4)&0xF].start.len = (val_ + 4);
          if(val_ == 0)
            CLIO.fifo_i[(addr_>>4)&0xF].start.len = 0;

          /* see patent WO09410641A1, 46.25 */
          CLIO.fifo_i[(addr_>>4)&0xF].next.len = 0;
          break;
        case 0x08:
          CLIO.fifo_i[(addr_>>4)&0xF].next.addr = val_;
          break;
        case 0x0C:
          if(val_ != 0)
            CLIO.fifo_i[(addr_>>4)&0xF].next.len = (val_ + 4);
          else
            CLIO.fifo_i[(addr_>>4)&0xF].next.len = 0;
          break;
        }
    }
  else
    {
      switch (addr_ & 0xF)
        {
        case 0x00:
          CLIO.fifo_o[(addr_>>4)&0xF].start.addr = val_;
          break;
        case 0x04:
          CLIO.fifo_o[(addr_>>4)&0xF].start.len  = (val_ + 4);
          break;
        case 0x08:
          CLIO.fifo_o[(addr_>>4)&0xF].next.addr  = val_;
          break;
        case 0x0C:
          CLIO.fifo_o[(addr_>>4)&0xF].next.len   = (val_ + 4);
          break;
        }
    }
}
