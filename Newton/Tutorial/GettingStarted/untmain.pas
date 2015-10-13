unit untMain;

{$mode objfpc}{$H+}

interface

uses
  LMessages, Classes, SysUtils, FileUtil, Forms, Controls, Graphics, Dialogs,
  avRes, avModel, avTypes, mutils, NewtonIntf, avCameraController, avPlatform;

type

  { TfrmMain }

  TfrmMain = class(TForm)
    ApplicationProperties: TApplicationProperties;
    procedure ApplicationPropertiesIdle(Sender: TObject; var Done: Boolean);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormPaint(Sender: TObject);
  private
    FMain: TavMainRender;
    FFBO : TavFrameBuffer;
    FProgram: TavProgram;
    FModels: TavModelCollection;

    FNWorld: INewtonWorld;

    FCubes: array [0..1] of IavModelInstance;
    FBodies: array [0..1] of INewtonBody;

    FLastPhysicsTime: Int64;
  protected
    procedure WMEraseBkgnd(var Message: TLMEraseBkgnd); message LM_ERASEBKGND;
  public
    procedure RenderScene;
    procedure InitWorld;
    procedure UpdatePhysics;

    procedure GravityForce(const ASource: INewtonBody; timestep : Single; threadIndex : Integer);
    procedure BodyTransform(const ASource: INewtonBody; const ATransform: TMat4; threadIndex : Integer);
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.lfm}

{$R '..\Common\MeshShader\shaders.res'}

{ TfrmMain }

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  FMain := TavMainRender.Create(nil);
  FMain.Window := Handle;
  FMain.Init3D(apiDX11);

  FFBO := Create_FrameBuffer(FMain, [TTextureFormat.RGBA, TTextureFormat.D32f]);

  FProgram := TavProgram.Create(FMain);
  FProgram.LoadFromJSON('avMesh', True);

  FModels := TavModelCollection.Create(FMain);
  FModels.AddFromFile(ExtractFilePath(ParamStr(0))+'\..\..\Common\bodies.avm');

  with TavCameraController.Create(FMain) do
  begin
    CanRotate := True;
  end;

  InitWorld;
end;

procedure TfrmMain.ApplicationPropertiesIdle(Sender: TObject; var Done: Boolean);
begin
  if Assigned(FNWorld) then
  begin
    UpdatePhysics;
    Done := True;
  end;
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
  FreeAndNil(FMain);
end;

procedure TfrmMain.FormPaint(Sender: TObject);
begin
  RenderScene;
end;

procedure TfrmMain.WMEraseBkgnd(var Message: TLMEraseBkgnd);
begin

end;

procedure TfrmMain.RenderScene;
begin
  if FMain = nil then Exit;
  if not FMain.Inited3D then Exit;
  if FMain.Bind then
  try
    FMain.States.DepthTest := True;

    FFBO.FrameRect := RectI(0, 0, ClientWidth, ClientHeight);
    FFBO.Select;
    FFBO.Clear(0, Black);
    FFBO.ClearDS(1);

    FProgram.Select;

    FModels.Select;
    FModels.Draw(FCubes);

    FFBO.BlitToWindow(0);
    FMain.Present;
  finally
    FMain.Unbind;
  end;
end;

procedure TfrmMain.InitWorld;
var CubeCollision: INewtonCollision;
    FloorTrasform: TMat4;
begin
  FNWorld := Create_NewtonWorld(AABB(Vec(-1.0,-1.0,-1.0)*1000.0, Vec(1.0,1.0,1.0)*1000.0));

  CubeCollision := FNWorld.CreateBox(Vec(1,1,1), IdentityMat4);

  FloorTrasform := Mat(Vec(1.0,0,0)*1000.0, Vec(0,1.0,0), Vec(0,0,1.0)*1000.0, Vec(0,-20,0));
  FCubes[0] := FModels.CreateInstance('Cube', FloorTrasform);
  FBodies[0] := FNWorld.CreateBody(CubeCollision, FloorTrasform);

  FCubes[1] := FModels.CreateInstance('Cube', IdentityMat4);
  FBodies[1] := FNWorld.CreateBody(CubeCollision, IdentityMat4);
  FBodies[1].CalcDefaultInertia(10.0);

  FBodies[1].OnApplyForce := @GravityForce;
  FBodies[1].OnTransform := @BodyTransform;
end;

procedure TfrmMain.UpdatePhysics;
const FRAME_STEP = 10;
var dTime: Int64;
begin
  dTime := GetTime64 - FLastPhysicsTime;
  while dTime > FRAME_STEP do
  begin
    FNWorld.UpdateWorld(FRAME_STEP/1000);
    Inc(FLastPhysicsTime, FRAME_STEP);
    Dec(dTime, FRAME_STEP);
  end;
  if Assigned(FMain) then
    FMain.InvalidateWindow;
end;

procedure TfrmMain.GravityForce(const ASource: INewtonBody; timestep: Single; threadIndex: Integer);
var m: Single;
    i: TVec3;
    gravity: TVec3;
begin
  ASource.GetMassMatrix(m, i);
  gravity := Vec(0,-9.8,0)*m;
  ASource.SetForce(gravity);
end;

procedure TfrmMain.BodyTransform(const ASource: INewtonBody; const ATransform: TMat4; threadIndex: Integer);
var i : Integer;
begin
  for i := 0 to Length(FBodies) - 1 do
  begin
    if FBodies[i] = ASource then
      FCubes[i].Transform := ATransform;
  end;
end;

end.

