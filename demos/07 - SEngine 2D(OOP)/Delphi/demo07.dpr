// ���� ������ ���������� �����������, �� ����������� ����, ��� ����������
// ���������� �������� �� ������ ������� �� ���������� extra
program demo07;

uses
  zglSpriteEngine, // ���� ������ ����� � ���������� extra
  zgl_main,
  zgl_screen,
  zgl_window,
  zgl_timers,
  zgl_keyboard,
  zgl_render_2d,
  zgl_fx,
  zgl_textures,
  zgl_textures_png, // ������ ������, ����������� ���� ��� ���������� ������ � ���������� ������� ������� ������
  zgl_textures_jpg,
  zgl_sprite_2d,
  zgl_primitives_2d,
  zgl_font,
  zgl_text,
  zgl_math_2d,
  zgl_utils;

type
  CMiku = class(zglCSprite2D)
  protected
    FSpeed : zglTPoint2D;
  public
    procedure OnInit( const _Texture : zglPTexture; const _Layer : Integer ); override;
    procedure OnDraw; override;
    procedure OnProc; override;
    procedure OnFree; override;
  end;

var
  fntMain   : zglPFont;
  texLogo   : zglPTexture;
  texMiku   : zglPTexture;
  time      : Integer;
  sengine2d : zglCSEngine2D;

// Miku
procedure CMiku.OnInit;
begin
  // ������ ���� �������� � Layer ��� �������, ������ ����������� �����������
  // ��������� ����� ������ � ������ �� ������ ������ � ����� � ��������
  inherited OnInit( texMiku, random( 10 ) );

  X     := 800 + random( 800 );
  Y     := random( 600 - 128 );
  // ������ �������� ��������
  FSpeed.X := -random( 10 ) / 5 - 0.5;
  FSpeed.Y := ( random( 10 ) - 5 ) / 5;
end;

procedure CMiku.OnDraw;
begin
  // �.�. �� ���� ��� ��������� ��������� ������ ��� �������, �� ������� ��������
  // ����� OnDraw ������ zglCSprite2D
  inherited;
end;

procedure CMiku.OnProc;
begin
  inherited;
  X := X + FSpeed.X;
  Y := Y + FSpeed.Y;
  Frame := Frame + ( abs( FSpeed.X ) + abs( FSpeed.Y ) ) / 25;
  if Frame > 8 Then
    Frame := 1;
  // ���� ������ ������� �� ������� �� X, ����� �� ������� ���
  if X < -128 Then sengine2d.DelSprite( ID );
  // ���� ������ ������� �� ������� �� Y, ������ ��� � ������� �� ��������
  if Y < -128 Then Destroy := TRUE;
  if Y > 600  Then Destroy := TRUE;
end;

procedure CMiku.OnFree;
begin
  inherited;
end;

// �������� 100 ��������
procedure AddMiku;
  var
    i, ID : Integer;
begin
  for i := 1 to 100 do
    begin
      // ����������� � ����������� ��������� ����� "�����" ��� ������ :)
      ID := sengine2d.AddSprite;
      // ������� ��������� ������� CMiku. ����������� ������������ ��������
      // ��� �������� � ������� ID ��� �������
      sengine2d.List[ ID ]:= CMiku.Create( sengine2d, ID );
    end;
end;

// ������� 100 ��������
procedure DelMiku;
  var
    i : Integer;
begin
  // ������ 100 �������� �� ��������� ID
  for i := 1 to 100 do
    sengine2d.DelSprite( random( sengine2d.Count ) );
end;

procedure Init;
  var
    i : Integer;
begin
  texLogo := tex_LoadFromFile( '../res/zengl.png', $FF000000, TEX_DEFAULT_2D );

  texMiku := tex_LoadFromFile( '../res/miku.png', $FF000000, TEX_DEFAULT_2D );
  tex_SetFrameSize( texMiku, 128, 128 );

  // ������� ��������� zglCSEngine2D
  sengine2d := zglCSEngine2D.Create;
  // �������� 1000 �������� Miku-chan :)
  for i := 0 to 9 do
    AddMiku;

  fntMain := font_LoadFromFile( '../res/font.zfi' );
  for i := 0 to fntMain.Count.Pages - 1 do
    fntMain.Pages[ i ] := tex_LoadFromFile( '../res/font_' + u_IntToStr( i ) + '.png', $FF000000, TEX_DEFAULT_2D );
end;

procedure Draw;
  var
    i : Integer;
    t : Single;
begin
  batch2d_Begin;

  // ������ ��� ������� ����������� � ������� ���������� ���������
  if time > 255 Then
    sengine2d.Draw;

  if time <= 255 Then
    ssprite2d_Draw( texLogo, 400 - 256, 300 - 128, 512, 256, 0, time )
  else
    if time < 510 Then
      begin
        pr2d_Rect( 0, 0, 800, 600, $000000, 510 - time, PR2D_FILL );
        ssprite2d_Draw( texLogo, 400 - 256, 300 - 128, 512, 256, 0, 510 - time );
      end;

  if time > 255 Then
    begin
      pr2d_Rect( 0, 0, 256, 64, $000000, 200, PR2D_FILL );
      text_Draw( fntMain, 0, 0, 'FPS: ' + u_IntToStr( zgl_Get( SYS_FPS ) ) );
      text_Draw( fntMain, 0, 20, 'Sprites: ' + u_IntToStr( sengine2d.Count ) );
      text_Draw( fntMain, 0, 40, 'Up/Down - Add/Delete Miku :)' );
    end;
  batch2d_End;
end;

procedure Timer;
  var
    i : Integer;
begin
  INC( time, 2 );

  // ��������� ��������� ���� �������� � ������� ���������� ���������
  sengine2d.Proc;
  // �� ������� ������� �������� ��� �������
  if key_Press( K_SPACE ) Then sengine2d.ClearAll;
  if key_Press( K_UP ) Then AddMiku;
  if key_Press( K_DOWN ) Then DelMiku;
  if key_Press( K_ESCAPE ) Then zgl_Exit;
  key_ClearState;
end;

Begin
  randomize;

  timer_Add( @Timer, 16 );
  timer_Add( @AddMiku, 1000 );

  zgl_Reg( SYS_LOAD, @Init );
  zgl_Reg( SYS_DRAW, @Draw );

  wnd_SetCaption( '07 - SEngine 2D(OOP)' );

  wnd_ShowCursor( TRUE );

  scr_SetOptions( 800, 600, REFRESH_MAXIMUM, FALSE, FALSE );

  zgl_Init;
End.
