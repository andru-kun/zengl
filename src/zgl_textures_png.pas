{
 *  Copyright © Kemka Andrey aka Andru
 *  mail: dr.andru@gmail.com
 *  site: http://zengl.org
 *
 *  This file is part of ZenGL.
 *
 *  ZenGL is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU Lesser General Public License as
 *  published by the Free Software Foundation, either version 3 of
 *  the License, or (at your option) any later version.
 *
 *  ZenGL is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU Lesser General Public License for more details.
 *
 *  You should have received a copy of the GNU Lesser General Public
 *  License along with ZenGL. If not, see http://www.gnu.org/licenses/
}
unit zgl_textures_png;

{$I zgl_config.cfg}

interface
uses
  {$IFDEF WINDESKTOP}
  zgl_lib_msvcrt,
  {$ENDIF}
  zgl_lib_zip,
  zgl_memory;

const
  PNG_EXTENSION : array[ 0..3 ] of Char = ( 'P', 'N', 'G', #0 );

procedure png_LoadFromFile( const FileName : String; var Data : Pointer; var W, H, Format : Word );
procedure png_LoadFromMemory( const Memory : zglTMemory; var Data : Pointer; var W, H, Format : Word );

implementation
uses
  zgl_main,
  zgl_types,
  zgl_file,
  zgl_log,
  zgl_textures;

threadvar
  pngBitDepth     : Integer;
  pngHastRNS      : Boolean;
  pngPalette      : array[ 0..255, 0..2 ] of Byte;
  pngPaletteAlpha : Byte;

const
  PNG_SIGNATURE : array[ 0..7 ] of AnsiChar = ( #137, #80, #78, #71, #13, #10, #26, #10 );

  PNG_FILTER_NONE    = 0;
  PNG_FILTER_SUB     = 1;
  PNG_FILTER_UP      = 2;
  PNG_FILTER_AVERAGE = 3;
  PNG_FILTER_PAETH   = 4;

  PNG_COLOR_GRAYSCALE      = 0;
  PNG_COLOR_RGB            = 2;
  PNG_COLOR_PALETTE        = 3;
  PNG_COLOR_GRAYSCALEALPHA = 4;
  PNG_COLOR_RGBALPHA       = 6;

type
  zglTPNGChunkName = array[ 0..3 ] of AnsiChar;

  zglPPNGChunk = ^zglTPNGChunk;
  zglTPNGChunk = record
    Name : zglTPNGChunkName;
    Size : Integer;
  end;

  zglTPNGHeader = packed record
    Width             : Integer;
    Height            : Integer;
    BitDepth          : Byte;
    ColorType         : Byte;
    CompressionMethod : Byte;
    FilterMethod      : Byte;
    InterlaceMethod   : Byte;
  end;

  PColor = ^TColor;
  TColor = record
    R, G, B, A : Byte;
  end;

procedure png_GetPixelInfo( var pngHeader : zglTPNGHeader; var pngRowSize, pngOffset : LongWord );
begin
  case pngHeader.ColorType of
    PNG_COLOR_GRAYSCALE:
      begin
        pngRowSize := ( pngHeader.Width * pngHeader.BitDepth + 7 ) div 8;
        if pngHeader.BitDepth = 16 Then
          pngOffset := 2
        else
          pngOffset := 1;
      end;
    PNG_COLOR_PALETTE:
      begin
        pngRowSize := ( pngHeader.Width * pngHeader.BitDepth + 7 ) div 8;
        pngOffset  := 1;
      end;
    PNG_COLOR_RGB:
      begin
        pngRowSize := ( pngHeader.Width * pngHeader.BitDepth * 3) div 8;
        pngOffset  := 3 * pngHeader.BitDepth div 8;
      end;
    PNG_COLOR_GRAYSCALEALPHA:
      begin
        pngRowSize := ( pngHeader.Width * pngHeader.BitDepth * 2 ) div 8;
        pngOffset  := 2 * pngHeader.BitDepth div 8;
      end;
    PNG_COLOR_RGBALPHA:
      begin
        pngRowSize := ( pngHeader.Width * pngHeader.BitDepth * 4 ) div 8;
        pngOffset  := 4 * pngHeader.BitDepth div 8;
      end;
  else
    pngRowsize := 0;
    pngOffset  := 0;
  end;
end;

procedure png_CopyNonInterlacedRGB( Src, Dest : PByte; Width : Integer );
  var
    i     : Integer;
    Color : PColor;
begin
  Color := Pointer( Dest );
  for i := 0 to Width - 1 do
    begin
      Color.R := Src^; INC( Src );
      Color.G := Src^; INC( Src );
      Color.B := Src^; INC( Src );
      Color.A := 255;
      INC( Color );
    end;
end;

procedure png_CopyNonInterlacedRGBAlpha( Src, Dest : PByte; Width : Integer );
begin
  Move( Src^, Dest^, Width * 4 );
end;

procedure png_CopyNonInterlacedPalette( Src, Dest : PByte; Width : Integer );
  var
    i : Integer;
    ByteData, N, K : Byte;
begin
  N := ( 8 div pngBitDepth );
  K := ( 8 - pngBitDepth );

  for i := 0 to Width - 1 do
    begin
      ByteData := PByteArray( Src )^[ i div N ];

      if pngBitDepth < 8 Then
        begin
          ByteData := ( ByteData Shr ( ( 8 - pngBitDepth ) - ( i mod N ) * pngBitDepth ) );
          ByteData := ByteData and ( $FF Shr K );
        end;

      Byte( Dest^ ) := pngPalette[ ByteData, 0 ]; INC( Dest );
      Byte( Dest^ ) := pngPalette[ ByteData, 1 ]; INC( Dest );
      Byte( Dest^ ) := pngPalette[ ByteData, 2 ]; INC( Dest );
      if ( pngPalette[ ByteData, 0 ] = pngPalette[ pngPaletteAlpha, 0 ] ) and
         ( pngPalette[ ByteData, 1 ] = pngPalette[ pngPaletteAlpha, 1 ] ) and
         ( pngPalette[ ByteData, 2 ] = pngPalette[ pngPaletteAlpha, 2 ] ) and pngHastRNS Then
        Byte( Dest^ ) := 0
      else
        Byte( Dest^ ) := 255;
      INC( Dest );
    end;
end;

procedure png_CopyNonInterlacedGrayscaleAlpha( Src, Dest : PByte; Width : Integer );
  var
    i     : Integer;
    Color : PColor;
begin
  Color := Pointer( Dest );
  for i := 0 to Width - 1 do
    begin
      Color.R := Src^;
      Color.G := Src^;
      Color.B := Src^; INC( Src );
      Color.A := Src^; INC( Src );
      INC( Color );
    end;
end;

procedure png_FilterRow( var pngRowBuffer : PByteArray; var pngRowBufferPrev : PByteArray; pngRowSize, pngOffset : LongWord );
  var
    i                          : Integer;
    Paeth                      : Integer;
    PP, Left, Above, AboveLeft : Integer;

  function PaethPredictor( a, b, c : Integer ) : Integer; {$IFDEF USE_INLINE} inline; {$ENDIF}
    var
      p, pa, pb, pc : Integer;
  begin
    p  := a + b - c;
    pa := abs( p - a );
    pb := abs( p - b );
    pc := abs( p - c );
    if ( pa <= pb ) and ( pa <= pc ) Then
      Result := a
    else
      if pb <= pc Then
        Result := b
      else
        Result := c;
  end;
begin
  case pngRowBuffer[ 0 ] of
    PNG_FILTER_NONE:;

    PNG_FILTER_SUB:
      for i := pngOffset + 1 to pngRowSize do
        pngRowBuffer[ i ] := ( pngRowBuffer[ i ] + pngRowBuffer[ i - pngOffset] ) and 255;

    PNG_FILTER_UP:
      for i := 1 to pngRowSize do
        pngRowBuffer[ i ] := ( pngRowBuffer[ i ] + pngRowBufferPrev[ i ] ) and 255;

    PNG_FILTER_AVERAGE:
      for i := 1 to pngRowSize do
        begin
          Above := pngRowBufferPrev[ i ];
          if i - 1 < pngOffset Then
            Left := 0
          else
            Left := pngRowBuffer[ i - pngOffset ];

          pngRowBuffer[ i ] := ( pngRowBuffer[ i ] + ( Left + Above ) div 2 ) and $FF;
        end;

    PNG_FILTER_PAETH:
      begin
        Left      := 0;
        AboveLeft := 0;

        for i := 1 to pngRowSize do
          begin
            if i - 1 >= pngOffset Then
              begin
                Left      := pngRowBuffer[ i - pngOffset];
                AboveLeft := pngRowBufferPrev[ i - pngOffset];
              end;

            Above := pngRowBufferPrev[ i ];

            Paeth := pngRowBuffer[ i ];
            PP    := PaethPredictor( Left, Above, AboveLeft );

            pngRowBuffer[ i ] := ( Paeth + PP ) and $FF;
          end;
      end;
  end;
end;

function png_ReadIHDR( var pngMem : zglTMemory; var pngHeader : zglTPNGheader; var Data : Pointer; Size : Integer ) : Boolean;
  var
    i : Integer;
begin
  if Size < SizeOf( zglTPNGHeader ) Then
    begin
      log_Add( 'PNG - Invalid header size' );
      Result := FALSE;
      exit;
    end;

  mem_ReadSwap( pngMem, pngHeader.Width, 4 );
  mem_ReadSwap( pngMem, pngHeader.Height, 4 );
  mem_Read( pngMem, pngHeader.BitDepth, 1 );
  mem_Read( pngMem, pngHeader.ColorType, 1 );
  mem_Read( pngMem, pngHeader.CompressionMethod, 1 );
  mem_Read( pngMem, pngHeader.FilterMethod, 1 );
  mem_Read( pngMem, pngHeader.InterlaceMethod, 1 );
  pngBitDepth := pngHeader.BitDepth;
  GetMem( Data, pngHeader.Width * pngHeader.Height * 4 );

  mem_Seek( pngMem, Size - SizeOf( zglTPNGHeader ), FSM_CUR );

  if ( pngHeader.CompressionMethod <> 0 ) Then
    begin
      log_Add( 'PNG - Invalid compression method' );
      Result := FALSE;
      exit;
    end;

  if pngHeader.InterlaceMethod <> 0 Then
    begin
      log_Add( 'PNG - Interlace not supported.' );
      Result := FALSE;
      exit;
    end;

  if pngHeader.ColorType = PNG_COLOR_GRAYSCALE Then
    for i := 0 to 255 do
      begin
        pngPalette[ i, 0 ] := i;
        pngPalette[ i, 1 ] := i;
        pngPalette[ i, 2 ] := i;
      end;

  Result := TRUE;
end;

procedure png_ReadPLTE( var pngMem : zglTMemory; Size : Integer );
begin
  mem_Read( pngMem, pngPalette[ 0 ], Size );
end;

function png_ReadIDAT( var pngMem : zglTMemory; pngHeader : zglTPNGHeader; var Data : Pointer; Size : Integer ) : Boolean;
  var
    i            : Cardinal;
    CopyP        : procedure( Src, Dest : PByte; Width : Integer );
    pngIDATEnd   : LongWord;
    pngZStream   : z_stream_s;
    pngRowUsed   : Boolean;
    pngRowBuffer : array[ Boolean ] of PByteArray;
    pngRowSize   : LongWord;
    pngOffset    : LongWord;
begin
  Result     := TRUE;
  CopyP      := nil;
  pngRowUsed := TRUE;
  pngIDATEnd := pngMem.Position + Size;
  png_GetPixelInfo( pngHeader, pngRowSize, pngOffset );

  zlib_Init( pngZStream );

  zgl_GetMem( Pointer( pngRowBuffer[ FALSE ] ), pngRowSize + 1 );
  zgl_GetMem( Pointer( pngRowBuffer[ TRUE ] ), pngRowSize + 1 );

  case pngHeader.ColorType of
    PNG_COLOR_RGB:
      if pngHeader.BitDepth = 8 Then CopyP := png_CopyNonInterlacedRGB;
    PNG_COLOR_PALETTE, PNG_COLOR_GRAYSCALE:
      if ( pngHeader.BitDepth = 1 ) or ( pngHeader.BitDepth = 4 ) or ( pngHeader.BitDepth = 8 ) Then CopyP := png_CopyNonInterlacedPalette;
    PNG_COLOR_RGBALPHA:
      if pngHeader.BitDepth = 8 Then CopyP := png_CopyNonInterlacedRGBAlpha;
    PNG_COLOR_GRAYSCALEALPHA:
      if pngHeader.BitDepth = 8 Then CopyP := png_CopyNonInterlacedGrayscaleAlpha;
  else
    log_Add( 'PNG - Unsupported ColorType' );
    Result := FALSE;
  end;

  if Result Then
    for i := pngHeader.Height downto 1 do
      begin
        if png_DecodeIDAT( pngMem, pngZStream, pngIDATEnd, @pngRowBuffer[ pngRowUsed ][ 0 ], pngRowsize + 1 ) < 0 Then
          begin
            log_Add( 'PNG - Failed to decode IDAT chunk' );
            Result := FALSE;
            break;
          end;

        png_FilterRow( pngRowBuffer[ pngRowUsed ], pngRowBuffer[ not pngRowUsed ], pngRowSize, pngOffset );

        CopyP( @pngRowBuffer[ pngRowUsed ][ 1 ], Pointer( Ptr( Data ) + pngHeader.Width * 4 * ( i - 1 ) ), pngHeader.Width );

        pngRowUsed := not pngRowUsed;
      end;

  FreeMem( pngRowBuffer[ FALSE ] );
  FreeMem( pngRowBuffer[ TRUE ] );

  zlib_Free( pngZStream );
end;

procedure png_ReadtRNS( var pngMem : zglTMemory; Size : Integer );
begin
  mem_Read( pngMem, pngPaletteAlpha, Size );
  pngHastRNS := TRUE;
end;

procedure png_LoadFromFile( const FileName : String; var Data : Pointer; var W, H, Format : Word );
  var
    pngMem : zglTMemory;
begin
  mem_LoadFromFile( pngMem, FileName );
  png_LoadFromMemory( pngMem, Data, W, H, Format );
  mem_Free( pngMem );
end;

procedure png_LoadFromMemory( const Memory : zglTMemory; var Data : Pointer; var W, H, Format : Word );
  label _exit;
  var
    pngMem          : zglTMemory;
    pngSignature    : array[ 0..7 ] of AnsiChar;
    pngHeader       : zglTPNGHeader;
    pngHasIDAT      : Boolean;
    pngChunk        : zglTPNGChunk;
    pngHeaderOk     : Boolean;
begin
  {$IFDEF ENDIAN_BIG}
  forceNoSwap := TRUE;
  {$ENDIF}
  pngMem      := Memory;
  pngHasIDAT  := FALSE;
  pngHeaderOk := FALSE;
  mem_Read( pngMem, pngSignature[ 0 ], 8 );

  if pngSignature <> PNG_SIGNATURE Then
    begin
      log_Add( 'PNG - Invalid header' );
      goto _exit;
    end;

  repeat
    mem_ReadSwap( pngMem, pngChunk.Size, 4 );
    mem_Read( pngMem, pngChunk.Name, 4 );

    if ( not pngHeaderOk ) and ( pngChunk.Name <> 'IHDR' ) Then
      begin
        log_Add( 'PNG - Header not found' );
        goto _exit;
      end;

    if ( pngHasIDAT and ( pngChunk.Name = 'IDAT' ) ) or ( pngChunk.Name = 'cHRM' ) Then
      begin
        mem_Seek( pngMem, pngChunk.Size + 4, FSM_CUR );
        continue;
      end;

    if pngChunk.Name = 'IDAT' Then pngHasIDAT := TRUE;

    if pngChunk.Name = 'IHDR' Then
      pngHeaderOk := png_ReadIHDR( pngMem, pngHeader, Data, pngChunk.Size )
    else
      if pngChunk.Name = 'PLTE' Then
        png_ReadPLTE( pngMem, pngChunk.Size )
      else
        if pngChunk.Name = 'IDAT' Then
          begin
            if not png_ReadIDAT( pngMem, pngHeader, Data, pngChunk.Size ) Then
              begin
                FreeMem( Data );
                Data := nil;
                goto _exit;
              end;
          end else
            if pngChunk.Name = 'tRNS' Then
              png_ReadtRNS( pngMem, pngChunk.Size )
            else
              mem_Seek( pngMem, pngChunk.Size, FSM_CUR );

    mem_Seek( pngMem, 4, FSM_CUR );
  until ( pngChunk.Name = 'IEND' );

  if not pngHasIDAT Then
    begin
      log_Add( 'PNG - Image data not found' );
      goto _exit;
    end;

  W      := pngHeader.Width;
  H      := pngHeader.Height;
  Format := TEX_FORMAT_RGBA;

_exit:
  begin
    pngHastRNS  := FALSE;
    {$IFDEF ENDIAN_BIG}
    forceNoSwap := FALSE;
    {$ENDIF}
  end;
end;

{$IFDEF USE_PNG}
initialization
  zgl_Reg( TEX_FORMAT_EXTENSION,   @PNG_EXTENSION[ 0 ] );
  zgl_Reg( TEX_FORMAT_FILE_LOADER, @png_LoadFromFile );
  zgl_Reg( TEX_FORMAT_MEM_LOADER,  @png_LoadFromMemory );
{$ENDIF}

end.
