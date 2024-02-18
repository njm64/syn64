#include <stdio.h>
#include <assert.h>
#include <string.h>
#include <stdbool.h>
#include <stdint.h>

//----------------------------------------------------------------------------
// Disk layout constants
// The maximum size of the bytecode is 64KB (256 sectors). This fits
// on 13 tracks. The first 13 tracks have 21 sectors each, giving us a
// total of 273 sectors. To keep things simple, we assume that the
// interpreter fits on a single track (14).
//----------------------------------------------------------------------------

#define SECTOR_SIZE       256
#define NUM_SECTORS       683
#define SECTOR_INTERLEAVE 10
#define TRACK_MIN         1
#define TRACK_MAX         35
#define TRACK_DATA_FIRST  1
#define TRACK_DATA_LAST   13
#define TRACK_PRG         14
#define TRACK_DIR         18
#define MAX_DATA_SIZE     65536
#define MAX_PRG_SIZE      (21 * SECTOR_SIZE)

#define OP_SET  1
#define OP_NOP  21

static uint8_t g_data[SECTOR_SIZE * NUM_SECTORS];

static int sectorsForTrack(int track) {
  assert(track >= TRACK_MIN && track <= TRACK_MAX);
  if(track <= 17) {
    return 21;
  } else if(track <= 24) {
    return 19;
  } else if(track <= 30) {
    return 18;
  } else {
    return 17;
  }
}

static uint8_t* getTrack(int track) {
  uint8_t* p = g_data;
  for(int t = TRACK_MIN; t < track; t++) {
    p += (sectorsForTrack(t) * SECTOR_SIZE);
  }
  return p;
}

static uint8_t* getSector(int track, int sector) {
  assert(track >= TRACK_MIN && track <= TRACK_MAX);
  assert(sector >= 0 && sector < sectorsForTrack(track));
  return getTrack(track) + sector * SECTOR_SIZE;
}

static void writePaddedString(uint8_t* dst, size_t size, const char* src) {
  size_t len = strlen(src);
  assert(len <= size);
  memcpy(dst, src, len);
  for(size_t i = len; i < size; i++) {
    dst[i] = 0xA0;
  }
}

static bool isTrackUsed(int track) {
  if(track >= TRACK_DATA_FIRST && track <= TRACK_DATA_LAST) {
    return true;
  } else if (track == TRACK_DIR || track == TRACK_PRG) {
    return true;
  } else {
    return false;
  }
}

static void writeBAM() {
  uint8_t* bam = getSector(TRACK_DIR, 0);
  bam[0x00] = 0x12;    // First directory entry track
  bam[0x01] = 0x01;    // First directory entry sector
  bam[0x02] = 0x41;    // Disk DOS version
  bam[0x03] = 0x00;    // Unused
  
  uint8_t* p = bam + 4;
  for(int t = TRACK_MIN; t <= TRACK_MAX; t++, p += 4) {
    if(isTrackUsed(t)) {
      p[0] = sectorsForTrack(t); // Free sectors for this track
      p[1] = 0xff;  // Availability bitmask
      p[2] = 0xff;  // Availability bitmask
      p[3] = 0xff;  // Availability bitmask
    }
  }

  // Disk name
  writePaddedString(bam + 0x90, 16, "SYNACOR");

  bam[0xA0] = 0xA0;
  bam[0xA1] = 0xA0;
  bam[0xA2] = 'S';   // Disk ID
  bam[0xA3] = 'C';   // Disk ID
  bam[0xA4] = 0xA0;
  bam[0xA5] = '2';   // Dos type
  bam[0xA6] = 'A';   // Dos type
  
  for(int i = 0xA7; i <= 0xAA; i++) {
    bam[i] = 0xA0;
  }
}

static void writeDirectorySector(int blocks) {
  uint8_t* dir = getSector(TRACK_DIR, 1);
  dir[0x00] = 0x00; // Next dir track (none)
  dir[0x01] = 0xFF; // Next dir sector (none)
  dir[0x02] = 0x82; // PRG
  dir[0x03] = TRACK_PRG; // Starting track of file
  dir[0x04] = 0x00; // Starting sector of file
  writePaddedString(dir + 0x05, 16, "CHALLENGE");
  dir[0x1E] = blocks; // File size in blocks
}

static int writeProgram(int track, const uint8_t* data, size_t size) {
  int sector = 0;
  int offset = 0;
  int numSectors = sectorsForTrack(track);
  int blocks = 0;

  while(true) {
    uint8_t* s = getSector(track, sector);
    int bytesRemaining = size - offset;

    // We can fit 254 bytes in each sector. If this is the last
    // sector, then write 0 for the track, and write the actual
    // number of bytes + 1 to the sector field.

    if(bytesRemaining <= 254) {
      s[0] = 0;
      s[1] = bytesRemaining + 1; 
      memcpy(s + 2, data + offset, bytesRemaining);
      blocks++;
      return blocks;
    }
  
    // Otherwise write 254 bytes to this sector, with a pointer
    // to the next one.

    sector = (sector + SECTOR_INTERLEAVE) % numSectors;
    s[0] = track;
    s[1] = sector;
    memcpy(s + 2, data + offset, 254);
    offset += 254;
    blocks++;
  }
}

static uint16_t readWord(uint16_t offset) {
  return g_data[offset * 2] | (g_data[offset * 2 + 1] << 8);
}

static void writeWord(uint16_t offset, uint16_t word) {
  g_data[offset * 2] = word & 0xff;
  g_data[offset * 2 + 1] = word >> 8;
}

static void decrypt() {
  // Decrypt the encrypted section of bytecode
  for(uint16_t addr = 0x17CA; addr < 0x7505; addr++) {
    uint16_t w = readWord(addr);
    w = w ^ (addr * addr) ^ 0x4154;
    writeWord(addr, w);
  }

  // Patch out the call to the original decrypt routine
  writeWord(0x038B, OP_NOP);
  writeWord(0x038C, OP_NOP);
}

static void patchTeleporter() {

  // Patch the instruction at 1561. It checks to ensure that R7 is non-zero,
  // and if so, the teleporter code is skipped. Instead, we set R7 to the
  // correct value, as calculated by tel.cpp.
  // old: 1561: OP_JF R7 15FB
  // new: 1561: OP_SET R7 6486
  writeWord(0x1561, OP_SET);
  writeWord(0x1563, 0x6486);

  // Remove the call to the teleporter confirmation routine, and the check
  // that it returns the correct value (6).
  // 1587: OP_CALL 17A1
  // 1589: OP_EQ R1 R0 0006
  // 158D: OP_JF R1 15E1
  for(uint16_t addr = 0x1587; addr <= 0x158F; addr++) {
    writeWord(addr, OP_NOP);
  }
}

static int readFile(const char* filename, uint8_t* buf, size_t size) {
  FILE* f = fopen(filename, "rb");
  if(!f) {
    printf("Failed to open %s\n", filename);
    return -1;
  }

  int bytes = fread(buf, 1, size, f);
  if(bytes < 0) {
    printf("Error reading from %s\n", filename);
    fclose(f);
    return -1;
  }

  fclose(f);
  return bytes;
}

int main(int argc, char** argv) {

  if(argc != 4) {
    printf("Usage: makedisk <challenge.bin> <vm.prg> <output.d64>\n");
    return 1;
  }

  int dataSize = readFile(argv[1], g_data, 65536);
  if(dataSize < 0) {
    return 1;
  }

  decrypt();
  patchTeleporter();

  uint8_t prg[MAX_PRG_SIZE];
  int prgSize = readFile(argv[2], prg, sizeof(prg));
  if(prgSize < 0) {
    return 1;
  }

  int blocks = writeProgram(TRACK_PRG, prg, prgSize);
  writeBAM();
  writeDirectorySector(blocks);

  FILE* f = fopen(argv[3], "wb");
  if(!f) {
    printf("Failed to open %s\n", argv[3]);
    return 1;
  }

  if(!fwrite(g_data, sizeof(g_data), 1, f)) {
    printf("Failed to write %s\n", argv[3]);
    fclose(f);
    return 1;
  }

  fclose(f);
  return 0;
}


