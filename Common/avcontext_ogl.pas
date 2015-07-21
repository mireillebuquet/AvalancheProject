unit avContext_OGL;
//{$DEFINE NOVAO}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, avTypes, avPlatform, dglOpenGL, Windows, mutils, avContext, avContnrs;

type
  TavInterfacedObject = TInterfacedObject;

  TObjListHash_func = specialize TMurmur2Hash<TObject>;
  TObjListHash = specialize THashMap<TObject, Boolean, TObjListHash_func>;
  IObjListHash = specialize IHashMap<TObject, Boolean, TObjListHash_func>;

  { TContext_OGL }

  TContext_OGL = class (TavInterfacedObject, IRenderContext)
  private
    FWnd : TWindow;
    FDC  : HDC;
    FRC  : HGLRC;

    FStates: TObject;
    FStatesIntf: IRenderStates;

    FBindCount: Integer;

    FHandles: IObjListHash;
    FPrograms: TList;
    FDeletedHandles: TList;

    FActiveProgram: IctxProgram;

    procedure AddHandle(const HandleObject: TObject);
    procedure RemoveHandle(const HandleObject: TObject);
    procedure AddHandlesForCleanup(const HandleObject: TObject);

    procedure CleanUpHandles;
    function GetActiveProgram: IctxProgram;
    procedure SetActiveProgram(AValue: IctxProgram);
  public
    function CreateVertexBuffer : IctxVetexBuffer;
    function CreateIndexBuffer : IctxIndexBuffer;
    function CreateProgram : IctxProgram;
    function CreateTexture : IctxTexture;
    function CreateFrameBuffer : IctxFrameBuffer;

    function States : IRenderStates;
    property ActiveProgram: IctxProgram read GetActiveProgram write SetActiveProgram;

    function Binded: Boolean;
    function Bind: Boolean;
    function Unbind: Boolean;

    procedure Clear(const color  : TVec4;      doColor  : Boolean = True;
                          depth  : Single = 1; doDepth  : Boolean = False;
                          stencil: Byte   = 0; doStencil: Boolean = False);
    procedure Present;

    constructor Create(Const Wnd: TWindow);
    destructor Destroy; override;
  end;

  TVAOKey = record
    ModelVertex   : IctxVetexBuffer;
    ModelIndex    : IctxIndexBuffer;
    InstanceVertex: IctxVetexBuffer;
    InstanceStepRate: Integer;
  end;
  TVAOInfo = record
    VAO: Cardinal;
    BindTime  : Cardinal;
    Model     : IDataLayout;
    Instance  : IDataLayout;
    HasIndices: Boolean;
  end;

operator = (const a, b: TVAOKey): Boolean;
operator = (const a, b: TVAOInfo): Boolean;

implementation

uses SuperObject, avLog;

const
  GLPoolType: array [TBufferPoolType] of Cardinal = ( {StaticDraw }  GL_STATIC_DRAW,
                                                      {DynamicDraw}  GL_DYNAMIC_DRAW,
                                                      {StreamDraw }  GL_STREAM_DRAW
                                                    );
  GLPrimitiveType: array [TPrimitiveType] of Cardinal = ( {ptPoints}            GL_POINTS,
                                                          {ptLines}             GL_LINES,
                                                          {ptLineStrip}         GL_LINE_STRIP,
                                                          {ptTriangles}         GL_TRIANGLES,
                                                          {ptTriangleStrip}     GL_TRIANGLE_STRIP,
                                                          {ptLines_Adj}         GL_LINES_ADJACENCY,
                                                          {ptLineStrip_Adj}     GL_LINE_STRIP_ADJACENCY,
                                                          {ptTriangles_Adj}     GL_TRIANGLES_ADJACENCY,
                                                          {ptTriangleStrip_Adj} GL_TRIANGLE_STRIP_ADJACENCY);
  GLIndexSize: array [TIndexSize] of Cardinal = ( {Word}  GL_UNSIGNED_SHORT,
                                                  {DWord} GL_UNSIGNED_INT);
  GLTextureFormat: array [TTextureFormat] of Cardinal = (  {RGBA   } GL_RGBA,
                                                           {RGBA16 } GL_RGBA16,
                                                           {RGBA16f} GL_RGBA16F,
                                                           {RGBA32 } GL_RGBA32UI,
                                                           {RGBA32f} GL_RGBA32F,
                                                           {RGB    } GL_RGB,
                                                           {RGB16  } GL_RGB16,
                                                           {RGB16f } GL_RGB16F,
                                                           {RGB32  } GL_RGB32UI,
                                                           {RGB32f } GL_RGB32F,
                                                           {RG     } GL_RG,
                                                           {RG16   } GL_RG16,
                                                           {RG16f  } GL_RG16F,
                                                           {RG32   } GL_RG32UI,
                                                           {RG32f  } GL_RG32F,
                                                           {R      } GL_RED,
                                                           {R16    } GL_R16,
                                                           {R16f   } GL_R16F,
                                                           {R32    } GL_R32UI,
                                                           {R32f   } GL_R32F,
                                                           {DXT1   } GL_COMPRESSED_RGBA_S3TC_DXT1_EXT,
                                                           {DXT3   } GL_COMPRESSED_RGBA_S3TC_DXT3_EXT,
                                                           {DXT5   } GL_COMPRESSED_RGBA_S3TC_DXT5_EXT,
                                                           {D24_S8 } GL_DEPTH24_STENCIL8,
                                                           {D32f_S8} GL_DEPTH32F_STENCIL8,
                                                           {D16    } GL_DEPTH_COMPONENT16,
                                                           {D24    } GL_DEPTH_COMPONENT24,
                                                           {D32    } GL_DEPTH_COMPONENT32,
                                                           {D32f   } GL_DEPTH_COMPONENT32F
                                                       );
  GLMapAccess: array [TMapingUsage] of Cardinal = ({muWriteOnly}GL_WRITE_ONLY,
                                                   {muReadOnly} GL_READ_ONLY,
                                                   {muReadWrite}GL_READ_WRITE);

const
  GLCompTypeSize: array [TComponentType] of Integer = ({ctBool}  1,
                                                       {ctByte}  1,
                                                       {ctUByte} 1,
                                                       {ctShort} 2,
                                                       {ctUShort}2,
                                                       {ctInt}   4,
                                                       {ctUInt}  4,
                                                       {ctFloat} 4,
                                                       {ctDouble}8);


operator = (const a, b: TVAOKey): Boolean;
begin
  Result := CompareMem(@a, @b, SizeOf(TVAOKey));
end;
operator = (const a, b: TVAOInfo): Boolean;
begin
  Result := CompareMem(@a, @b, SizeOf(TVAOInfo));
end;


procedure VectorInfoOfDataType(datatype: Cardinal; out ElementClass: TDataClass;
                                                   out ElementType: TComponentType;
                                                   out ElementsCount: Integer);
begin
  case datatype of
    GL_FLOAT,
    GL_FLOAT_VEC2,
    GL_FLOAT_VEC3,
    GL_FLOAT_VEC4,
    GL_FLOAT_MAT2,
    GL_FLOAT_MAT3,
    GL_FLOAT_MAT4,
    GL_FLOAT_MAT2x3,
    GL_FLOAT_MAT2x4,
    GL_FLOAT_MAT3x2,
    GL_FLOAT_MAT3x4,
    GL_FLOAT_MAT4x2,
    GL_FLOAT_MAT4x3: ElementType := ctFloat;

    GL_DOUBLE,
    GL_DOUBLE_VEC2,
    GL_DOUBLE_VEC3,
    GL_DOUBLE_VEC4,
    GL_DOUBLE_MAT2,
    GL_DOUBLE_MAT3,
    GL_DOUBLE_MAT4,
    GL_DOUBLE_MAT2x3,
    GL_DOUBLE_MAT2x4,
    GL_DOUBLE_MAT3x2,
    GL_DOUBLE_MAT3x4,
    GL_DOUBLE_MAT4x2,
    GL_DOUBLE_MAT4x3: ElementType := ctDouble;

    GL_INT,
    GL_INT_VEC2,
    GL_INT_VEC3,
    GL_INT_VEC4,
    GL_SAMPLER_1D,
    GL_SAMPLER_2D,
    GL_SAMPLER_3D,
    GL_SAMPLER_CUBE,
    GL_SAMPLER_1D_SHADOW,
    GL_SAMPLER_2D_SHADOW,
    GL_SAMPLER_1D_ARRAY,
    GL_SAMPLER_2D_ARRAY,
    GL_SAMPLER_1D_ARRAY_SHADOW,
    GL_SAMPLER_2D_ARRAY_SHADOW,
    GL_SAMPLER_2D_MULTISAMPLE,
    GL_SAMPLER_2D_MULTISAMPLE_ARRAY,
    GL_SAMPLER_CUBE_SHADOW,
    GL_SAMPLER_BUFFER,
    GL_SAMPLER_2D_RECT,
    GL_SAMPLER_2D_RECT_SHADOW,
    GL_INT_SAMPLER_1D,
    GL_INT_SAMPLER_2D,
    GL_INT_SAMPLER_3D,
    GL_INT_SAMPLER_CUBE,
    GL_INT_SAMPLER_1D_ARRAY,
    GL_INT_SAMPLER_2D_ARRAY,
    GL_INT_SAMPLER_2D_MULTISAMPLE,
    GL_INT_SAMPLER_2D_MULTISAMPLE_ARRAY,
    GL_INT_SAMPLER_BUFFER,
    GL_INT_SAMPLER_2D_RECT,
    GL_UNSIGNED_INT_SAMPLER_1D,
    GL_UNSIGNED_INT_SAMPLER_2D,
    GL_UNSIGNED_INT_SAMPLER_3D,
    GL_UNSIGNED_INT_SAMPLER_CUBE,
    GL_UNSIGNED_INT_SAMPLER_1D_ARRAY,
    GL_UNSIGNED_INT_SAMPLER_2D_ARRAY,
    GL_UNSIGNED_INT_SAMPLER_2D_MULTISAMPLE,
    GL_UNSIGNED_INT_SAMPLER_2D_MULTISAMPLE_ARRAY,
    GL_UNSIGNED_INT_SAMPLER_BUFFER,
    GL_UNSIGNED_INT_SAMPLER_2D_RECT : ElementType := ctInt;

    GL_UNSIGNED_INT,
    GL_UNSIGNED_INT_VEC2,
    GL_UNSIGNED_INT_VEC3,
    GL_UNSIGNED_INT_VEC4: ElementType := ctUInt;

    GL_BOOL,
    GL_BOOL_VEC2,
    GL_BOOL_VEC3,
    GL_BOOL_VEC4: ElementType := ctBool;
  else
    Assert(False, 'Uknown element type '+IntToHex(datatype, 0));
  end;

  case datatype of
    GL_FLOAT,
    GL_DOUBLE,
    GL_INT,
    GL_UNSIGNED_INT,
    GL_BOOL : ElementClass := dcScalar;

    GL_FLOAT_VEC2,
    GL_FLOAT_VEC3,
    GL_FLOAT_VEC4,
    GL_DOUBLE_VEC2,
    GL_DOUBLE_VEC3,
    GL_DOUBLE_VEC4,
    GL_INT_VEC2,
    GL_INT_VEC3,
    GL_INT_VEC4,
    GL_UNSIGNED_INT_VEC2,
    GL_UNSIGNED_INT_VEC3,
    GL_UNSIGNED_INT_VEC4,
    GL_BOOL_VEC2,
    GL_BOOL_VEC3,
    GL_BOOL_VEC4 : ElementClass := dcVector;


    GL_FLOAT_MAT2,
    GL_FLOAT_MAT3,
    GL_FLOAT_MAT4,
    GL_FLOAT_MAT2x3,
    GL_FLOAT_MAT2x4,
    GL_FLOAT_MAT3x2,
    GL_FLOAT_MAT3x4,
    GL_FLOAT_MAT4x2,
    GL_FLOAT_MAT4x3,
    GL_DOUBLE_MAT2,
    GL_DOUBLE_MAT3,
    GL_DOUBLE_MAT4,
    GL_DOUBLE_MAT2x3,
    GL_DOUBLE_MAT2x4,
    GL_DOUBLE_MAT3x2,
    GL_DOUBLE_MAT3x4,
    GL_DOUBLE_MAT4x2,
    GL_DOUBLE_MAT4x3: ElementClass := dcMatrix;

    GL_SAMPLER_1D,
    GL_SAMPLER_2D,
    GL_SAMPLER_3D,
    GL_SAMPLER_CUBE,
    GL_SAMPLER_1D_SHADOW,
    GL_SAMPLER_2D_SHADOW,
    GL_SAMPLER_1D_ARRAY,
    GL_SAMPLER_2D_ARRAY,
    GL_SAMPLER_1D_ARRAY_SHADOW,
    GL_SAMPLER_2D_ARRAY_SHADOW,
    GL_SAMPLER_2D_MULTISAMPLE,
    GL_SAMPLER_2D_MULTISAMPLE_ARRAY,
    GL_SAMPLER_CUBE_SHADOW,
    GL_SAMPLER_BUFFER,
    GL_SAMPLER_2D_RECT,
    GL_SAMPLER_2D_RECT_SHADOW,
    GL_INT_SAMPLER_1D,
    GL_INT_SAMPLER_2D,
    GL_INT_SAMPLER_3D,
    GL_INT_SAMPLER_CUBE,
    GL_INT_SAMPLER_1D_ARRAY,
    GL_INT_SAMPLER_2D_ARRAY,
    GL_INT_SAMPLER_2D_MULTISAMPLE,
    GL_INT_SAMPLER_2D_MULTISAMPLE_ARRAY,
    GL_INT_SAMPLER_BUFFER,
    GL_INT_SAMPLER_2D_RECT,
    GL_UNSIGNED_INT_SAMPLER_1D,
    GL_UNSIGNED_INT_SAMPLER_2D,
    GL_UNSIGNED_INT_SAMPLER_3D,
    GL_UNSIGNED_INT_SAMPLER_CUBE,
    GL_UNSIGNED_INT_SAMPLER_1D_ARRAY,
    GL_UNSIGNED_INT_SAMPLER_2D_ARRAY,
    GL_UNSIGNED_INT_SAMPLER_2D_MULTISAMPLE,
    GL_UNSIGNED_INT_SAMPLER_2D_MULTISAMPLE_ARRAY,
    GL_UNSIGNED_INT_SAMPLER_BUFFER,
    GL_UNSIGNED_INT_SAMPLER_2D_RECT : ElementClass := dcSampler;
  else
    Assert(False, 'Uknown element type '+IntToHex(datatype, 0));
  end;

  case datatype of
    GL_FLOAT,
    GL_DOUBLE,
    GL_INT,
    GL_UNSIGNED_INT,
    GL_BOOL: ElementsCount := 1;

    GL_FLOAT_VEC2,
    GL_DOUBLE_VEC2,
    GL_INT_VEC2,
    GL_UNSIGNED_INT_VEC2,
    GL_BOOL_VEC2: ElementsCount := 2;

    GL_FLOAT_VEC3,
    GL_DOUBLE_VEC3,
    GL_INT_VEC3,
    GL_UNSIGNED_INT_VEC3,
    GL_BOOL_VEC3: ElementsCount := 3;

    GL_FLOAT_VEC4,
    GL_DOUBLE_VEC4,
    GL_INT_VEC4,
    GL_UNSIGNED_INT_VEC4,
    GL_BOOL_VEC4: ElementsCount := 4;

    GL_FLOAT_MAT2,
    GL_DOUBLE_MAT2: ElementsCount := 4;


    GL_FLOAT_MAT3,
    GL_DOUBLE_MAT3: ElementsCount := 9;

    GL_FLOAT_MAT4,
    GL_DOUBLE_MAT4: ElementsCount := 16;

    GL_FLOAT_MAT2x3,
    GL_FLOAT_MAT3x2,
    GL_DOUBLE_MAT2x3,
    GL_DOUBLE_MAT3x2: ElementsCount := 6;

    GL_FLOAT_MAT2x4,
    GL_FLOAT_MAT4x2,
    GL_DOUBLE_MAT2x4,
    GL_DOUBLE_MAT4x2: ElementsCount := 8;


    GL_FLOAT_MAT3x4,
    GL_FLOAT_MAT4x3,
    GL_DOUBLE_MAT3x4,
    GL_DOUBLE_MAT4x3: ElementsCount := 12;

    GL_SAMPLER_1D,
    GL_SAMPLER_2D,
    GL_SAMPLER_3D,
    GL_SAMPLER_CUBE,
    GL_SAMPLER_1D_SHADOW,
    GL_SAMPLER_2D_SHADOW,
    GL_SAMPLER_1D_ARRAY,
    GL_SAMPLER_2D_ARRAY,
    GL_SAMPLER_1D_ARRAY_SHADOW,
    GL_SAMPLER_2D_ARRAY_SHADOW,
    GL_SAMPLER_2D_MULTISAMPLE,
    GL_SAMPLER_2D_MULTISAMPLE_ARRAY,
    GL_SAMPLER_CUBE_SHADOW,
    GL_SAMPLER_BUFFER,
    GL_SAMPLER_2D_RECT,
    GL_SAMPLER_2D_RECT_SHADOW,
    GL_INT_SAMPLER_1D,
    GL_INT_SAMPLER_2D,
    GL_INT_SAMPLER_3D,
    GL_INT_SAMPLER_CUBE,
    GL_INT_SAMPLER_1D_ARRAY,
    GL_INT_SAMPLER_2D_ARRAY,
    GL_INT_SAMPLER_2D_MULTISAMPLE,
    GL_INT_SAMPLER_2D_MULTISAMPLE_ARRAY,
    GL_INT_SAMPLER_BUFFER,
    GL_INT_SAMPLER_2D_RECT,
    GL_UNSIGNED_INT_SAMPLER_1D,
    GL_UNSIGNED_INT_SAMPLER_2D,
    GL_UNSIGNED_INT_SAMPLER_3D,
    GL_UNSIGNED_INT_SAMPLER_CUBE,
    GL_UNSIGNED_INT_SAMPLER_1D_ARRAY,
    GL_UNSIGNED_INT_SAMPLER_2D_ARRAY,
    GL_UNSIGNED_INT_SAMPLER_2D_MULTISAMPLE,
    GL_UNSIGNED_INT_SAMPLER_2D_MULTISAMPLE_ARRAY,
    GL_UNSIGNED_INT_SAMPLER_BUFFER,
    GL_UNSIGNED_INT_SAMPLER_2D_RECT : ElementsCount := 1;
  else
    ElementsCount := 0;
  end;
end;

function SizeOfDataType(datatype: Cardinal): Integer;
var ElClass: TDataClass;
    ElType: TComponentType;
    ElCount: Integer;
begin
  VectorInfoOfDataType(datatype, ElClass, ElType, ElCount);

  Result := GLCompTypeSize[ElType] * ElCount;
end;

function ReduceName(const AName: string): string;
var n: Integer;
begin
    n := Pos('[', AName);
    if n > 1 then
    begin
        Result := Copy(AName, 1, n - 1);
        Exit;
    end;
    n := Pos('.', AName);
    if n > 1 then
    begin
        Result := Copy(AName, 1, n - 1);
        Exit;
    end;
    Result := AName;
end;

function GetErrorStr(errorcode: Cardinal): string;
begin
  Result := '('+IntToHex(errorcode, 8)+')';
end;

function GetGLErrorStr(errorcode: Cardinal): string;
begin
  case ErrorCode of
    GL_NO_ERROR                      : Result := 'GL_NO_ERROR';
    GL_INVALID_ENUM                  : Result := 'GL_INVALID_ENUM';
    GL_INVALID_VALUE                 : Result := 'GL_INVALID_VALUE';
    GL_INVALID_OPERATION             : Result := 'GL_INVALID_OPERATION';
    GL_INVALID_FRAMEBUFFER_OPERATION : Result := 'GL_INVALID_FRAMEBUFFER_OPERATION';
    GL_OUT_OF_MEMORY                 : Result := 'GL_OUT_OF_MEMORY';
    GL_STACK_UNDERFLOW               : Result := 'GL_STACK_UNDERFLOW';
    GL_STACK_OVERFLOW                : Result := 'GL_STACK_OVERFLOW';
  else
    Result := GetErrorStr(errorcode);
  end;
end;

procedure Raise3DError(const msg: string);
begin
  raise E3DError.Create(msg);
end;

procedure RaiseLast3DError(const prefix: string);
begin
  Raise3DError(prefix + GetGLErrorStr(glGetError()));
end;

type

  { TNoRefObject }

  TNoRefObject = class (TObject, IUnknown)
    function QueryInterface({$IFDEF FPC_HAS_CONSTREF}constref{$ELSE}const{$ENDIF} iid : tguid;out obj) : longint;{$IFNDEF WINDOWS}cdecl{$ELSE}stdcall{$ENDIF};
    function _AddRef : longint;{$IFNDEF WINDOWS}cdecl{$ELSE}stdcall{$ENDIF};
    function _Release : longint;{$IFNDEF WINDOWS}cdecl{$ELSE}stdcall{$ENDIF};
  end;

  { TStates_OGL }

  TStates_OGL = class (TNoRefObject, IRenderStates)
  private
    const
      GLCompareFunction : array [TCompareFunc] of Cardinal = (
        GL_NEVER,    // cfNever
        GL_LESS,     // cfLess
        GL_EQUAL,    // cfEqual
        GL_NOTEQUAL, // cfNotEqual
        GL_LEQUAL,   // cfLessEqual
        GL_GREATER,  // cfGreater
        GL_GEQUAL,   // cfGreaterEqual
        GL_ALWAYS    // cfAlways
      );

      GLStencilAction : array [TStencilAction] of Cardinal = (
        GL_KEEP,      // saKeep
        GL_REPLACE,   // saSet
        GL_ZERO,      // saZero
        GL_INVERT,    // saInvert
        GL_INCR,      // saInc
        GL_DECR,      // saDec
        GL_INCR_WRAP, // saIncWrap
        GL_DECR_WRAP  // saDecWrap
      );

      GLBlendFunction : array [TBlendFunc] of Cardinal = (
        GL_ZERO,                // bfZero
        GL_ONE,                 // bfOne
        GL_SRC_ALPHA,           // bfSrcAlpha
        GL_ONE_MINUS_SRC_ALPHA  // bfInvSrcAlpha
      );
  private
    FContext      : TContext_OGL;
    FCullMode     : TCullingMode;
    FLineWidth    : Single;
    FVertexProgramPointSize: Boolean;
    FColorWrite   : Boolean;
    FDepthWrite   : Boolean;
    FDepthTest    : Boolean;
    FDepthFunc    : TCompareFunc;
    FNearFarClamp : Boolean;
    FBlendSrc     : TBlendFunc;
    FBlendDest    : TBlendFunc;
    FBlending     : Boolean;
    FViewport     : TRect;
    FWireframe    : Boolean;
    FScissor      : Boolean;
    FStencil      : Boolean;
    function GetBlendDest: TBlendFunc;
    function GetBlending: Boolean;
    function GetBlendSrc: TBlendFunc;
    function GetColorWrite: Boolean;
    function GetCullMode: TCullingMode;
    function GetDepthFunc: TCompareFunc;
    function GetDepthTest: Boolean;
    function GetDepthWrite: Boolean;
    function GetLineWidth: Single;
    function GetNearFarClamp: Boolean;
    function GetVertexProgramPointSize: Boolean;
    function GetViewport: TRect;
    function GetWireframe: Boolean;
    procedure SetCullMode(const Value: TCullingMode);
    procedure SetLineWidth(const Value: Single);
    procedure SetVertexProgramPointSize(const Value: Boolean);
    procedure SetColorWrite(const Value: Boolean);
    procedure SetDepthTest(const Value: Boolean);
    procedure SetDepthWrite(const Value: Boolean);
    procedure SetDepthFunc(const Value: TCompareFunc);
    procedure SetNearFarClamp(const Value: Boolean);
    procedure SetBlending(const Value: Boolean);
    procedure SetViewport(const Value: TRect);
    procedure SetWireframe(const Value: Boolean);
  public
    procedure SetBlendFunctions(Src, Dest: TBlendFunc);

    constructor Create(AContext: TContext_OGL);

    procedure ReadDefaultStates;

    procedure SetScissor(Enabled: Boolean; const Value: TRect);
    procedure SetStencil(Enabled: Boolean; StencilFunc: TCompareFunc; Ref: Integer; Mask: Byte; sFail, dFail, dPass: TStencilAction);
  end;

  { IHandle }

  IHandle = interface
  ['{F2CF8FAC-F7E7-49AF-846F-439DBFFB289A}']
    function Handle: Cardinal;
  end;

  { THandle }

  THandle = class(TObject, IUnknown, IHandle)
  private
    FRefCount: Integer;

    function Handle: Cardinal;
    function QueryInterface(constref iid: tguid; out obj): longint; stdcall;
    function _AddRef: longint; stdcall;
    function _Release: longint; stdcall;
  protected
    FContext: TContext_OGL;
    FHandle: Cardinal;

    procedure AllocHandle; virtual; abstract;
    procedure FreeHandle; virtual; abstract;
  public
    procedure AfterConstruction; override;
    constructor Create(AContext: TContext_OGL); overload; virtual;
    class function NewInstance: TObject; override;
    destructor Destroy; override;
  end;

  { TBufferBase }

  TBufferBase = class(THandle, IctxBuffer)
  protected
    const
        GLPoolType: array [TBufferPoolType] of Cardinal = ( {StaticDraw }  GL_STATIC_DRAW,
                                                            {DynamicDraw}  GL_DYNAMIC_DRAW,
                                                            {StreamDraw }  GL_STREAM_DRAW
                                                          );
        GLPrimitiveType: array [TPrimitiveType] of Cardinal = ( {ptPoints}            GL_POINTS,
                                                                {ptLines}             GL_LINES,
                                                                {ptLineStrip}         GL_LINE_STRIP,
                                                                {ptTriangles}         GL_TRIANGLES,
                                                                {ptTriangleStrip}     GL_TRIANGLE_STRIP,
                                                                {ptLines_Adj}         GL_LINES_ADJACENCY,
                                                                {ptLineStrip_Adj}     GL_LINE_STRIP_ADJACENCY,
                                                                {ptTriangles_Adj}     GL_TRIANGLES_ADJACENCY,
                                                                {ptTriangleStrip_Adj} GL_TRIANGLE_STRIP_ADJACENCY);
        GLIndexSize: array [TIndexSize] of Cardinal = ( {Word}  GL_UNSIGNED_SHORT,
                                                        {DWord} GL_UNSIGNED_INT);
  private
    FSize: Integer;
    FTargetPool: TBufferPoolType;
    function GetTargetPoolType: TBufferPoolType;
    procedure SetTargetPoolType(Value: TBufferPoolType);
  protected
    procedure AllocHandle; override;
    procedure FreeHandle; override;

    property TargetPoolType: TBufferPoolType read GetTargetPoolType write SetTargetPoolType;

    function Size: Integer;

    function Map(usage: TMapingUsage): PByte; virtual; abstract;
    function Unmap: Boolean; virtual; abstract;
    procedure AllocMem(ASize: Integer; Data: PByte); overload;
    procedure SetSubData(AOffset, ASize: Integer; Data: PByte); overload;
  end;

  { TVertexBuffer }

  TVertexBuffer = class(TBufferBase, IctxVetexBuffer)
  private
    FLayout: IDataLayout;
  public
    function Map(usage: TMapingUsage): PByte; override;
    function Unmap: Boolean; override;
  public
    function GetLayout: IDataLayout;
    procedure SetLayout(const Value: IDataLayout);

    function VertexCount: Integer;
    property Layout: IDataLayout read GetLayout write SetLayout;
  end;

  { TIndexBuffer }

  TIndexBuffer = class(TBufferBase, IctxIndexBuffer)
  private
    FIndexSize: TIndexSize;
    FPrimType: TPrimitiveType;
  public
    function Map(usage: TMapingUsage): PByte; override;
    function Unmap: Boolean; override;
  public
    //*******
    function GetIndexSize: TIndexSize;
    function GetPrimType: TPrimitiveType;
    procedure SetIndexSize(AValue: TIndexSize);
    procedure SetPrimType(AValue: TPrimitiveType);
    //*******
    function IndicesCount: Integer;
    function PrimCount: Integer;
    Property IndexSize: TIndexSize Read GetIndexSize Write SetIndexSize;
    property PrimType: TPrimitiveType read GetPrimType write SetPrimType;
  end;

  { TTexture }

  TTexture = class(THandle, IctxTexture)
  private const
    GLImagePixelFormat: array [TImageFormat] of Cardinal = ( {Unknown      }  GL_NONE,
                                                             {Gray8        }  GL_ALPHA,
                                                             {R3G3B2       }  GL_RGB,
                                                             {R8G8         }  GL_RG,
                                                             {R5G6B5       }  GL_RGB,
                                                             {A1R5G5B5     }  GL_BGRA,
                                                             {A4R4G4B4     }  GL_BGRA,
                                                             {R8G8B8       }  GL_BGR,
                                                             {B8G8R8A8     }  GL_BGRA,
                                                             {R8G8B8A8     }  GL_RGBA,
                                                             {R16          }  GL_RED,
                                                             {R16G16       }  GL_RG,
                                                             {R16G16B16    }  GL_BGR,  //??
                                                             {A16R16G16B16 }  GL_BGRA, //??
                                                             {B16G16R16    }  GL_RGB,  //??
                                                             {A16B16G16R16 }  GL_RGBA, //??
                                                             {R32          }  GL_RED,
                                                             {R32G32       }  GL_RG,
                                                             {R32G32B32    }  GL_RGB,
                                                             {A32R32G32B32F}  GL_RGBA,
                                                             {A32B32G32R32F}  GL_RGBA, //??
                                                             {DXT1         }  GL_COMPRESSED_RGBA_S3TC_DXT1_EXT,
                                                             {DXT3         }  GL_COMPRESSED_RGBA_S3TC_DXT3_EXT,
                                                             {DXT5         }  GL_COMPRESSED_RGBA_S3TC_DXT5_EXT
                                                           );
    GLImageComponentFormat: array [TImageFormat] of Cardinal = ( {Unknown      }  GL_NONE,
                                                                 {Gray8        }  GL_UNSIGNED_BYTE,
                                                                 {R3G3B2       }  GL_UNSIGNED_BYTE_2_3_3_REV,
                                                                 {R8G8         }  GL_UNSIGNED_BYTE,
                                                                 {R5G6B5       }  GL_UNSIGNED_SHORT_5_6_5,
                                                                 {A1R5G5B5     }  GL_UNSIGNED_SHORT_1_5_5_5_REV,
                                                                 {A4R4G4B4     }  GL_UNSIGNED_SHORT_4_4_4_4,
                                                                 {R8G8B8       }  GL_UNSIGNED_BYTE,
                                                                 {B8G8R8A8     }  GL_UNSIGNED_INT_8_8_8_8_REV,
                                                                 {R8G8B8A8     }  GL_UNSIGNED_BYTE,
                                                                 {R16          }  GL_UNSIGNED_SHORT,
                                                                 {R16G16       }  GL_UNSIGNED_SHORT,
                                                                 {R16G16B16    }  GL_UNSIGNED_SHORT,
                                                                 {A16R16G16B16 }  GL_UNSIGNED_SHORT,
                                                                 {B16G16R16    }  GL_UNSIGNED_SHORT,
                                                                 {A16B16G16R16 }  GL_UNSIGNED_SHORT,
                                                                 {R32          }  GL_FLOAT,
                                                                 {R32G32       }  GL_FLOAT,
                                                                 {R32G32B32    }  GL_FLOAT,
                                                                 {A32R32G32B32F}  GL_FLOAT,
                                                                 {A32B32G32R32F}  GL_FLOAT,
                                                                 {DXT1         }  GL_NONE,
                                                                 {DXT3         }  GL_NONE,
                                                                 {DXT5         }  GL_NONE
                                                               );
  private
    FFormat : TTextureFormat;
    FWidth  : Integer;
    FHeight : Integer;
    FTargetFormat : TTextureFormat;

    function GetTargetFormat: TTextureFormat;
    procedure SetTargetFormat(Value: TTextureFormat);

    procedure AllocMem(AWidth, AHeight: Integer; glFormat, exFormat, compFormat: Cardinal; Data: PByte; GenMipmaps: Boolean); overload;
  public
    procedure AllocHandle; override;
    procedure FreeHandle; override;

    property TargetFormat: TTextureFormat read GetTargetFormat write SetTargetFormat;

    function Width : Integer;
    function Height: Integer;
    function Format: TTextureFormat;

    procedure AllocMem(AWidth, AHeight: Integer; WithMips: Boolean); overload;
    procedure AllocMem(AWidth, AHeight: Integer; WithMips: Boolean; DataFormat: TImageFormat; Data: PByte); overload;
    procedure SetImage(ImageWidth, ImageHeight: Integer; DataFormat: TImageFormat; Data: PByte; GenMipmaps: Boolean); overload;
    procedure SetImage(X, Y, ImageWidth, ImageHeight: Integer; DataFormat: TImageFormat; Data: PByte; GenMipmaps: Boolean); overload;
    procedure SetMipImage(X, Y, ImageWidth, ImageHeight, MipLevel: Integer; DataFormat: TImageFormat; Data: PByte); overload;
    procedure SetMipImage(DestRect: TRect; MipLevel: Integer; DataFormat: TImageFormat; Data: PByte); overload;
  end;

  { TProgram }

  TProgram = class(THandle, IctxProgram)
  private
    type
      TUniformField_OGL = class (TUniformField)
      public
        FData: array of Byte;
        ID: Cardinal;
        OGLType: Cardinal;
      end;

      TAttributeField_OGL = class
          ID           : Integer;
          Name         : String;
          DataType     : Cardinal;
          DataClass    : TDataClass;
          ElementType  : TComponentType;
          ElementsCount: Integer;
      end;
    const
      GLComponentType: array [TComponentType] of Cardinal = ({ctBool}   GL_BOOL,
                                                             {ctByte}   GL_BYTE,
                                                             {ctUByte}  GL_UNSIGNED_BYTE,
                                                             {ctShort}  GL_SHORT,
                                                             {ctUShort} GL_UNSIGNED_SHORT,
                                                             {ctInt}    GL_INT,
                                                             {ctUInt}   GL_UNSIGNED_INT,
                                                             {ctFloat}  GL_FLOAT,
                                                             {ctDouble} GL_DOUBLE);
      GLMagTextureFilter : array [TTextureFilter] of Cardinal = (
        GL_NEAREST,
        GL_NEAREST,
        GL_LINEAR
      );
                                 //mip           //min
      GLMinTextureFilter: array [TTextureFilter, TTextureFilter] of Cardinal = ((GL_NEAREST,                GL_NEAREST,                GL_LINEAR),                     //no mips
                                                                                (GL_NEAREST_MIPMAP_NEAREST, GL_NEAREST_MIPMAP_NEAREST, GL_LINEAR_MIPMAP_NEAREST),      //nearest mip
                                                                                (GL_NEAREST_MIPMAP_LINEAR , GL_NEAREST_MIPMAP_LINEAR , GL_LINEAR_MIPMAP_LINEAR ) );    //linear mips
      GLWrap : array [TTextureWrap] of Cardinal = (
        GL_REPEAT,          // twRepeat
        GL_MIRRORED_REPEAT, // twMirror
        GL_CLAMP,           // twClamp}
        GL_CLAMP_TO_EDGE    // twClampToEdge
      );
    type
      TVaoHash_func = specialize TMurmur2Hash<TVAOKey>;
      TVaoHash = specialize THashMap<TVAOKey, TVAOInfo, TVaoHash_func>;
      IVaoHash = specialize IHashMap<TVAOKey, TVAOInfo, TVaoHash_func>;

      TStringHash_func = TMurmur2HashString;
      TUniformHash = specialize THashMap<string, TUniformField_OGL, TStringHash_func>;
      IUniformHash = specialize IHashMap<string, TUniformField_OGL, TStringHash_func>;
      TAttributeHash = specialize THashMap<string, TAttributeField_OGL, TStringHash_func>;
      IAttributeHash = specialize IHashMap<string, TAttributeField_OGL, TStringHash_func>;
  private
    FUniformList: IUniformHash;
    FAttrList: IAttributeHash;
    FVAOList : IVaoHash;
    FValidated: Boolean;

    FSelectedVAOKey: TVAOKey;
    FSelectedVAOBinded: Boolean;
  protected
    procedure ClearUniformList;
    procedure ClearAttrList;
    procedure ClearVAOList;

    function CreateShader(const ACode: AnsiString; AType: TShaderType): Cardinal;
    procedure DetachAllShaders;
    procedure ReadUniforms;
    procedure ReadAttributes;

    procedure BindVAO(const AKey: TVAOKey);

    function GetAttributeField(const name: string): TAttributeField_OGL;
    procedure SetAttribute(AttrField: TAttributeField_OGL; componentsCount, componentsType: integer; stride, offset: integer; divisor: Integer; normalized: Boolean = False); overload;
    procedure SetAttributes(const ALayout: IDataLayout; divisor: Integer); overload;

    function GetProgramInfoLog: string;

    procedure ValidateProgram;
    procedure CleanUpUselessVAO;
  protected
    procedure AllocHandle; override;
    procedure FreeHandle; override;
  public //IctxProgram
    procedure Select;
    procedure Load(const AProgram: string; FromResource: Boolean = false);

    procedure SetAttributes(const AModel, AInstances : IctxVetexBuffer; const AModelIndices: IctxIndexBuffer; InstanceStepRate: Integer = 1);

    function GetUniformField(const Name: string): TUniformField;
    procedure SetUniform(const Field: TUniformField; const Value: integer); overload;
    procedure SetUniform(const Field: TUniformField; const Value: single); overload;
    procedure SetUniform(const Field: TUniformField; const v: TVec2); overload;
    procedure SetUniform(const Field: TUniformField; const v: TVec3); overload;
    procedure SetUniform(const Field: TUniformField; const v: TVec4); overload;
    procedure SetUniform(const Field: TUniformField; const values: TSingleArr); overload;
    procedure SetUniform(const Field: TUniformField; const v: TVec4arr); overload;
    procedure SetUniform(const Field: TUniformField; const m: TMat4); overload;
    procedure SetUniform(const Field: TUniformField; const tex: IctxTexture; const Sampler: TSamplerInfo); overload;
    procedure Draw(PrimTopology: TPrimitiveType; CullMode: TCullingMode; IndexedGeometry: Boolean;
                   InstanceCount: Integer;
                   Start: integer; Count: integer;
                   BaseVertex: integer; BaseInstance: Integer);
  public
    constructor Create(AContext: TContext_OGL); override;
    destructor Destroy; override;
  end;

{ TTexture }

function TTexture.GetTargetFormat: TTextureFormat;
begin
  Result := FTargetFormat;
end;

procedure TTexture.SetTargetFormat(Value: TTextureFormat);
begin
  FTargetFormat := Value;
end;

procedure TTexture.AllocMem(AWidth, AHeight: Integer; glFormat, exFormat, compFormat: Cardinal; Data: PByte; GenMipmaps: Boolean);
begin
  glBindTexture(GL_TEXTURE_2D, FHandle);
  glTexImage2D(GL_TEXTURE_2D, 0, glFormat, AWidth, AHeight, 0, exFormat, compFormat, Data);
  FWidth := AWidth;
  FHeight := AHeight;
  FFormat := FTargetFormat;
  if GenMipmaps then
      glGenerateMipmap(GL_TEXTURE_2D);
end;

procedure TTexture.AllocHandle;
begin
  glGenTextures(1, @FHandle);
end;

procedure TTexture.FreeHandle;
begin
  glDeleteTextures(1, @FHandle);
  FHandle := 0;
end;

function TTexture.Width: Integer;
begin
  Result := FWidth;
end;

function TTexture.Height: Integer;
begin
  Result := FHeight;
end;

function TTexture.Format: TTextureFormat;
begin
  Result := FFormat;
end;

procedure TTexture.AllocMem(AWidth, AHeight: Integer; WithMips: Boolean);
var exFormat: Cardinal;
    compType: Cardinal;
begin
  case TargetFormat of
    TTextureFormat.D32f_S8 : begin exFormat:=GL_DEPTH_STENCIL;   compType:=GL_FLOAT_32_UNSIGNED_INT_24_8_REV; end;
    TTextureFormat.D24_S8  : begin exFormat:=GL_DEPTH_STENCIL;   compType:=GL_UNSIGNED_INT_24_8;              end;
    TTextureFormat.D16     : begin exFormat:=GL_DEPTH_COMPONENT; compType:=GL_UNSIGNED_SHORT;                 end;
    TTextureFormat.D24     : begin exFormat:=GL_DEPTH_COMPONENT; compType:=GL_UNSIGNED_BYTE;                  end;
    TTextureFormat.D32     : begin exFormat:=GL_DEPTH_COMPONENT; compType:=GL_INT;                            end;
    TTextureFormat.D32f    : begin exFormat:=GL_DEPTH_COMPONENT; compType:=GL_FLOAT;                          end;
    TTextureFormat.RGBA16f : begin exFormat:=GL_RGBA;            compType:=GL_HALF_FLOAT;                     end;
  else
    exFormat:=GL_RGBA; compType:=GL_UNSIGNED_BYTE;
  end;
  AllocMem(AWidth, AHeight, GLTextureFormat[FTargetFormat], exFormat, compType, nil, WithMips);
end;

procedure TTexture.AllocMem(AWidth, AHeight: Integer; WithMips: Boolean; DataFormat: TImageFormat; Data: PByte);
begin
  AllocMem(AWidth, AHeight, GLTextureFormat[FTargetFormat], GLImagePixelFormat[DataFormat], GLImageComponentFormat[DataFormat], Data, WithMips);
end;

procedure TTexture.SetImage(ImageWidth, ImageHeight: Integer; DataFormat: TImageFormat; Data: PByte; GenMipmaps: Boolean);
begin
  SetImage(0, 0, ImageWidth, ImageHeight, DataFormat, Data, GenMipmaps);
end;

procedure TTexture.SetImage(X, Y, ImageWidth, ImageHeight: Integer; DataFormat: TImageFormat; Data: PByte; GenMipmaps: Boolean);
var W, H: Integer;
begin
  W := NextPow2(ImageWidth);
  H := NextPow2(ImageHeight);
  if (W <> Width) or (H <> Height) or (Format <> TargetFormat) then
    AllocMem(W, H, False, DataFormat, nil);

  glBindTexture(GL_TEXTURE_2D, FHandle);
  glTexSubImage2D(GL_TEXTURE_2D, 0, X, Y, ImageWidth, ImageHeight, GLImagePixelFormat[DataFormat], GLImageComponentFormat[DataFormat], Data);
  if GenMipmaps then
    glGenerateMipmap(GL_TEXTURE_2D);
end;

procedure TTexture.SetMipImage(X, Y, ImageWidth, ImageHeight, MipLevel: Integer; DataFormat: TImageFormat; Data: PByte);
begin
  glBindTexture(GL_TEXTURE_2D, FHandle);
  glTexSubImage2D(GL_TEXTURE_2D, MipLevel, X, Y, ImageWidth, ImageHeight, GLImagePixelFormat[DataFormat], GLImageComponentFormat[DataFormat], Data);
end;

procedure TTexture.SetMipImage(DestRect: TRect; MipLevel: Integer; DataFormat: TImageFormat; Data: PByte);
begin
  SetMipImage(DestRect.Left, DestRect.Top, DestRect.Right - DestRect.Left, DestRect.Bottom - DestRect.Top, MipLevel, DataFormat, Data);
end;

{ TOGLStates }

function TStates_OGL.GetBlendDest: TBlendFunc;
begin
  Result := FBlendDest;
end;

function TStates_OGL.GetBlending: Boolean;
begin
  Result := FBlending;
end;

function TStates_OGL.GetBlendSrc: TBlendFunc;
begin
  Result := FBlendSrc;
end;

function TStates_OGL.GetColorWrite: Boolean;
begin
  Result := FColorWrite;
end;

function TStates_OGL.GetCullMode: TCullingMode;
begin
  Result := FCullMode;
end;

function TStates_OGL.GetDepthFunc: TCompareFunc;
begin
  Result := FDepthFunc;
end;

function TStates_OGL.GetDepthTest: Boolean;
begin
  Result := FDepthTest;
end;

function TStates_OGL.GetDepthWrite: Boolean;
begin
  Result := FDepthWrite;
end;

function TStates_OGL.GetLineWidth: Single;
begin
  Result := FLineWidth;
end;

function TStates_OGL.GetNearFarClamp: Boolean;
begin
  Result := FNearFarClamp;
end;

function TStates_OGL.GetVertexProgramPointSize: Boolean;
begin
  Result := FVertexProgramPointSize;
end;

function TStates_OGL.GetViewport: TRect;
begin
  Result := FViewport;
end;

function TStates_OGL.GetWireframe: Boolean;
begin
  Result := FWireframe;
end;

procedure TStates_OGL.SetCullMode(const Value: TCullingMode);
begin
  if (FCullMode <> Value) and FContext.Binded then
  begin
    case Value of
      cmNone: glDisable(GL_CULL_FACE);
      cmBack: begin
                glEnable(GL_CULL_FACE);
                glCullFace(GL_BACK);
              end;
      cmFront: begin
                glEnable(GL_CULL_FACE);
                glCullFace(GL_FRONT);
              end;
    end;
    FCullMode := Value;
  end;
end;

procedure TStates_OGL.SetLineWidth(const Value: Single);
begin
  if (FLineWidth <> Value) and FContext.Binded then
  begin
    FLineWidth := Value;
    glLineWidth(Value);
  end;
end;

procedure TStates_OGL.SetVertexProgramPointSize(const Value: Boolean);
begin
  if (FVertexProgramPointSize <> Value) and FContext.Binded then
  begin
    FVertexProgramPointSize := Value;
    if FVertexProgramPointSize then
      glEnable(GL_VERTEX_PROGRAM_POINT_SIZE)
    else
      glDisable(GL_VERTEX_PROGRAM_POINT_SIZE);
  end;
end;

procedure TStates_OGL.SetColorWrite(const Value: Boolean);
begin
  if (FColorWrite <> Value) and (FContext.Binded) then
  begin
    FColorWrite := Value;
    glColorMask(FColorWrite, FColorWrite, FColorWrite, FColorWrite);
  end;
end;

procedure TStates_OGL.SetDepthTest(const Value: Boolean);
begin
  if (FDepthTest <> Value) and FContext.Binded then
  begin
      FDepthTest := Value;
      if FDepthTest then
        glEnable(GL_DEPTH_TEST)
      else
        glDisable(GL_DEPTH_TEST);
  end;
end;

procedure TStates_OGL.SetDepthWrite(const Value: Boolean);
begin
  if (FDepthWrite <> Value) and FContext.Binded then
  begin
    FDepthWrite := Value;
    glDepthMask(FDepthWrite);
  end;
end;

procedure TStates_OGL.SetDepthFunc(const Value: TCompareFunc);
begin
  if (FDepthFunc <> Value) and FContext.Binded then
  begin
    FDepthFunc := Value;
    glDepthFunc(GLCompareFunction[FDepthFunc]);
  end;
end;

procedure TStates_OGL.SetNearFarClamp(const Value: Boolean);
begin
  if (FNearFarClamp <> Value) and FContext.Binded Then
  begin
    FNearFarClamp := Value;
    if FNearFarClamp then
      glEnable(GL_DEPTH_CLAMP)
    else
      glDisable(GL_DEPTH_CLAMP);
  end;
end;

procedure TStates_OGL.SetBlending(const Value: Boolean);
begin
  if (FBlending <> Value) and FContext.Binded Then
  begin
    FBlending := Value;
    if FBlending then
      glEnable(GL_BLEND)
    else
      glDisable(GL_BLEND);
  end;
end;

procedure TStates_OGL.SetViewport(const Value: TRect);
begin
  if ((FViewport.Left   <> Value.Left  ) or
      (FViewport.Top    <> Value.Top   ) or
      (FViewport.Right  <> Value.Right ) or
      (FViewport.Bottom <> Value.Bottom)) and FContext.Binded then
  begin
    FViewport := Value;
    glViewport(FViewport.Left, FViewport.Top, FViewport.Right - FViewport.Left, FViewport.Bottom - FViewport.Top);
  end;
end;

procedure TStates_OGL.SetWireframe(const Value: Boolean);
begin
  if Value <> FWireframe then
  begin
    FWireframe := Value;
    if FWireframe then
      glPolygonMode(GL_FRONT_AND_BACK, GL_LINE)
    else
      glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
  end;
end;

procedure TStates_OGL.SetBlendFunctions(Src, Dest: TBlendFunc);
begin
  if (Src <> FBlendSrc) and (Dest <> FBlendDest) and FContext.Binded then
  begin
    FBlendSrc := Src;
    FBlendDest := Dest;
    glBlendFunc( GLBlendFunction[Src], GLBlendFunction[Dest] );
  end;
end;

constructor TStates_OGL.Create(AContext: TContext_OGL);
begin
  FContext := AContext;
end;

procedure TStates_OGL.ReadDefaultStates;
var gb: GLboolean;
    gi: GLint;
    gf: GLfloat;
    colorwritemask: array [0..3] of GLboolean;
begin
  glGetBooleanv(GL_CULL_FACE, @gb);
  glGetIntegerv(GL_CULL_FACE_MODE, @gi);
  if gb then
    if (gi=GL_BACK) then
      FCullMode := cmBack
    else
      FCullMode := cmFront
  else
    FCullMode := cmNone;

  glGetFloatv(GL_LINE_WIDTH, @gf);
  FLineWidth := gf;

  //GL_VERTEX_PROGRAM_POINT_SIZE    not defined at glGet??
  FVertexProgramPointSize := False;

  glGetBooleanv(GL_COLOR_WRITEMASK, @colorwritemask[0]);
  FColorWrite := colorwritemask[0];

  glGetBooleanv(GL_DEPTH_TEST, @gb);
  FDepthTest := gb;

  glGetBooleanv(GL_DEPTH_WRITEMASK, @gb);
  FDepthWrite := gb;

  glGetIntegerv(GL_DEPTH_FUNC, @gi);
  case gi of
    GL_NEVER   : FDepthFunc := cfNever;
    GL_LESS    : FDepthFunc := cfLess;
    GL_EQUAL   : FDepthFunc := cfEqual;
    GL_LEQUAL  : FDepthFunc := cfLessEqual;
    GL_GREATER : FDepthFunc := cfGreater;
    GL_GEQUAL  : FDepthFunc := cfGreaterEqual;
    GL_ALWAYS  : FDepthFunc := cfAlways;
  else
    FDepthFunc := cfLess;
  end;

  //GL_DEPTH_CLAMP    not defined at glGet??
  FNearFarClamp := False;

  glGetBooleanv(GL_BLEND, @gb);
  FBlending := gb;

  //GL_BLEND_FUNC    not defined at glGet??
  FBlendSrc := bfOne;
  FBlendDest := bfZero;

  glGetIntegerv(GL_VIEWPORT, @FViewport);
  FViewport.Right := FViewport.Right + FViewport.Left;
  FViewport.Bottom := FViewport.Bottom + FViewport.Top;

  glGetIntegerv(GL_POLYGON_MODE, @gi);
  if gi = GL_LINE then
    FWireframe := True
  else
    FWireframe := False;
end;

procedure TStates_OGL.SetScissor(Enabled: Boolean; const Value: TRect);
begin
  if FScissor <> Enabled then
  begin
    FScissor := Enabled;
    if Enabled then
      glEnable(GL_SCISSOR_TEST)
    else
      glDisable(GL_SCISSOR_TEST);
  end;

  if FScissor then
    glScissor(Value.Left, Value.Top, Value.Right - Value.Left, Value.Bottom - Value.Top);
end;

procedure TStates_OGL.SetStencil(Enabled: Boolean; StencilFunc: TCompareFunc;
  Ref: Integer; Mask: Byte; sFail, dFail, dPass: TStencilAction);
begin
  if FStencil <> Enabled then
  begin
    FStencil := Enabled;
    if Enabled then
      glEnable(GL_STENCIL_TEST)
    else
      glDisable(GL_STENCIL_TEST);
  end;

  if FStencil then
  begin
    glStencilFunc(GLCompareFunction[StencilFunc], Ref, Mask);
    glStencilOp(GLStencilAction[sFail], GLStencilAction[dFail], GLStencilAction[dPass]);
  end;
end;

{ TNoRefObject }

function TNoRefObject.QueryInterface({$IFDEF FPC_HAS_CONSTREF}constref{$ELSE}const{$ENDIF} iid : tguid;out obj) : longint;{$IFNDEF WINDOWS}cdecl{$ELSE}stdcall{$ENDIF};
begin
  if GetInterface(IID, Obj) then
    Result := 0
  else
    Result := E_NOINTERFACE;
end;

function TNoRefObject._AddRef : longint;{$IFNDEF WINDOWS}cdecl{$ELSE}stdcall{$ENDIF};
begin
  Result := -1;
end;

function TNoRefObject._Release : longint;{$IFNDEF WINDOWS}cdecl{$ELSE}stdcall{$ENDIF};
begin
  Result := -1;
end;

{ TIndexBuffer }

function TIndexBuffer.Map(usage: TMapingUsage): PByte;
begin
  Assert(FContext.Binded);
  glBindVertexArray(0);
  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, FHandle);
  Result := glMapBuffer(GL_ELEMENT_ARRAY_BUFFER, GLMapAccess[usage]);
end;

function TIndexBuffer.Unmap: Boolean;
begin
  Assert(FContext.Binded);
  Result := glUnmapBuffer(GL_ELEMENT_ARRAY_BUFFER);
end;

function TIndexBuffer.GetIndexSize: TIndexSize;
begin
  Result := FIndexSize;
end;

function TIndexBuffer.GetPrimType: TPrimitiveType;
begin
  Result := FPrimType;
end;

function TIndexBuffer.IndicesCount: Integer;
begin
  case FIndexSize of
    TIndexSize.Word  : Result := FSize div 2;
    TIndexSize.DWord : Result := FSize div 2;
  else
    Assert(False, 'Not implemented yet');
  end;
end;

function TIndexBuffer.PrimCount: Integer;
begin
  Result := CalcPrimCount(IndicesCount, FPrimType);
end;

procedure TIndexBuffer.SetIndexSize(AValue: TIndexSize);
begin
  FIndexSize := AValue;
end;

procedure TIndexBuffer.SetPrimType(AValue: TPrimitiveType);
begin
  FPrimType := AValue;
end;

{ TVertexBufferHandle }

function TVertexBuffer.GetLayout: IDataLayout;
begin
  Result := FLayout;
end;

procedure TVertexBuffer.SetLayout(const Value: IDataLayout);
begin
  FLayout := Value;
end;

function TVertexBuffer.VertexCount: Integer;
begin
  Result := FSize div FLayout.Size;
end;

function TVertexBuffer.Map(usage: TMapingUsage): PByte;
begin
  Assert(FContext.Binded);
  glBindVertexArray(0);
  glBindBuffer(GL_ARRAY_BUFFER, FHandle);
  Result := glMapBuffer(GL_ARRAY_BUFFER, GLMapAccess[usage]);
end;

function TVertexBuffer.Unmap: Boolean;
begin
  Assert(FContext.Binded);
  Result := glUnmapBuffer(GL_ARRAY_BUFFER);
end;

{ TBufferHandle }

function TBufferBase.GetTargetPoolType: TBufferPoolType;
begin
  Result := FTargetPool;
end;

procedure TBufferBase.SetTargetPoolType(Value: TBufferPoolType);
begin
  FTargetPool := Value;
end;

procedure TBufferBase.AllocHandle;
begin
  glGenBuffers(1, @FHandle);
end;

procedure TBufferBase.FreeHandle;
begin
  glDeleteBuffers(1, @FHandle);
  FHandle := 0;
end;

function TBufferBase.Size: Integer;
begin
  Result := FSize;
end;

procedure TBufferBase.AllocMem(ASize: Integer; Data: PByte);
var ActiveObject: GLuint;
begin
  Assert(FContext.Binded);
  FSize := ASize;
  {$IFNDEF NOglNamed}
  if Assigned(glNamedBufferDataEXT) then
  begin
      glNamedBufferDataEXT(FHandle, ASize, Data, GLPoolType[FTargetPool]);
  end
  else
  {$ENDIF}
  begin
      {$IFDEF NOVAO}
      glGetIntegerv(GL_ARRAY_BUFFER_BINDING, @ActiveObject);
      if FHandle <> ActiveObject then glBindBuffer(GL_ARRAY_BUFFER, FHandle);
      glBufferData(GL_ARRAY_BUFFER, ASize, Data, GLPoolType[FTargetPool]);
      if FHandle <> ActiveObject then glBindBuffer(GL_ARRAY_BUFFER, ActiveObject);
      {$ELSE}
      glGetIntegerv(GL_VERTEX_ARRAY_BINDING, @ActiveObject);
      if ActiveObject <> 0 then glBindVertexArray(0);
      glBindBuffer(GL_ARRAY_BUFFER, FHandle);
      glBufferData(GL_ARRAY_BUFFER, ASize, Data, GLPoolType[FTargetPool]);
      glBindBuffer(GL_ARRAY_BUFFER, 0);
      if ActiveObject <> 0 then glBindVertexArray(ActiveObject);
      {$ENDIF}
  end;
end;

procedure TBufferBase.SetSubData(AOffset, ASize: Integer; Data: PByte);
var ActiveObject: GLuint;
begin
  Assert(FContext.Binded);
  {$IFNDEF NOglNamed}
  if Assigned(glNamedBufferSubDataEXT) then
  begin
      glNamedBufferSubDataEXT(FHandle, AOffset, ASize, Data);
  end
  else
  {$ENDIF}
  begin
      {$IFDEF NOVAO}
      glGetIntegerv(GL_ARRAY_BUFFER_BINDING, @ActiveObject);
      if FHandle <> ActiveObject then glBindBuffer(GL_ARRAY_BUFFER, FHandle);
      glBufferSubData(GL_ARRAY_BUFFER, AOffset, ASize, Data);
      if FHandle <> ActiveObject then glBindBuffer(GL_ARRAY_BUFFER, ActiveObject);
      {$ELSE}
      glGetIntegerv(GL_VERTEX_ARRAY_BINDING, @ActiveObject);
      if ActiveObject <> 0 then glBindVertexArray(0);
      glBindBuffer(GL_ARRAY_BUFFER, FHandle);
      glBufferSubData(GL_ARRAY_BUFFER, AOffset, ASize, Data);
      glBindBuffer(GL_ARRAY_BUFFER, 0);
      if ActiveObject <> 0 then glBindVertexArray(ActiveObject);
      {$ENDIF}
  end;
end;

{ TProgram }

procedure TProgram.ClearUniformList;
var Key: String;
    Value: TUniformField_OGL;
begin
  FUniformList.Reset;
  while FUniformList.Next(Key, Value) do Value.Free;
  FUniformList.Clear;
end;

procedure TProgram.ClearAttrList;
var Key: String;
    Value: TAttributeField_OGL;
begin
  FAttrList.Reset;
  while FAttrList.Next(Key, Value) do Value.Free;
  FAttrList.Clear;
end;

procedure TProgram.ClearVAOList;
begin
  FVAOList.Clear;
end;

function TProgram.CreateShader(const ACode: AnsiString; AType: TShaderType): Cardinal;
  function GetShaderCompileLog(const Shader: GLuint): string;
  var Log: AnsiString;
      n, tmplen: GLint;
  begin
      glGetShaderiv(Shader, GL_INFO_LOG_LENGTH, @n);
      if n>1 then
      begin
        SetLength(Log, n-1);
        glGetShaderInfoLog(Shader, n, tmplen, PAnsiChar(Log));
        Result := 'Shader compile log: ' + string(Log);
      end;
  end;
var n: Integer;
    CompRes: GLint;
    pstr: PAnsiChar;
    Log: string;
begin
  Result := 0;

  case AType of
      stVertex  : Result := glCreateShader(GL_VERTEX_SHADER);
      stFragment: Result := glCreateShader(GL_FRAGMENT_SHADER);
  else
    Assert(False, 'unknown shader type');
  end;
  if Result = 0 then RaiseLast3DError('TProgram.glCreateShader: ');

  n := Length(ACode);
  pstr := @ACode[1];
  glShaderSource(Result, 1, @pstr, @n);
  glCompileShader(Result);
  glGetShaderiv(Result, GL_COMPILE_STATUS, @CompRes);
  if CompRes = GL_FALSE then
  begin
    glDeleteShader(Result);
    Raise3DError('TProgram.glCompileShader: ' + GetShaderCompileLog(Result));
  end;

  Log := GetShaderCompileLog(Result);
  if Log <> '' then LogLn(Log);
end;

procedure TProgram.DetachAllShaders;
var i, cnt: Integer;
    shaders: array of Cardinal;
begin
  if FHandle <> 0 then
  begin
    glGetProgramiv(FHandle, GL_ATTACHED_SHADERS, @cnt);
    if cnt>0 then
    begin
      SetLength(shaders, cnt);
      glGetAttachedShaders(FHandle, cnt, cnt, @shaders[0]);
      for i := 0 to Length(shaders) - 1 do
        glDetachShader(FHandle, shaders[i]);
      for i := 0 to Length(shaders) - 1 do
        glDeleteShader(shaders[i]);
    end;
  end;
end;

procedure TProgram.ReadUniforms;
var uniform : TUniformField_OGL;
    I, N: Integer;
    namebuf_ans: AnsiString;
    namebuf: string;
    writenlen: Integer;
    datasize: integer;
    datatype: Cardinal;

    texIndex: Integer;
begin
  glGetProgramiv(FHandle, GL_ACTIVE_UNIFORM_MAX_LENGTH, @N);
  texIndex := 0;
  if N > 0 then
  begin
    glUseProgram(FHandle);

    SetLength(namebuf_ans, N - 1);
    glGetProgramiv(FHandle, GL_ACTIVE_UNIFORMS, @N);
    for I := 0 to N - 1 do
    begin
      uniform := TUniformField_OGL.Create;

      FillChar(namebuf_ans[1], Length(namebuf_ans), 0);
      glGetActiveUniform(FHandle, I, Length(namebuf_ans)+1, writenlen, datasize, datatype, @namebuf_ans[1]);
      namebuf := string(PAnsiChar(namebuf_ans));
      if Pos('gl_', namebuf) <> 1 then
      begin
        uniform.Name := ReduceName(namebuf);
        uniform.OGLType := datatype;
        VectorInfoOfDataType(datatype, uniform.DataClass, uniform.ElementType, uniform.ElementsCount);
        uniform.ItemsCount := datasize div (uniform.ElementsCount * GLCompTypeSize[uniform.ElementType]);
        SetLength(uniform.FData, datasize * SizeOfDataType(datatype));
        uniform.Data := @uniform.FData[0];
        uniform.DataSize := Length(uniform.FData);
        FillChar(uniform.FData[0], Length(uniform.FData), 0);
        uniform.ID := glGetUniformLocation(FHandle, @namebuf_ans[1]);

        case uniform.ElementType of
            ctBool  : glGetUniformfv (FHandle, uniform.ID, @uniform.Data[0]);
            ctByte  : glGetUniformiv (FHandle, uniform.ID, @uniform.Data[0]);
            ctUByte : glGetUniformuiv(FHandle, uniform.ID, @uniform.Data[0]);
            ctShort : glGetUniformiv (FHandle, uniform.ID, @uniform.Data[0]);
            ctUShort: glGetUniformuiv(FHandle, uniform.ID, @uniform.Data[0]);
            ctInt   : glGetUniformiv (FHandle, uniform.ID, @uniform.Data[0]);
            ctUInt  : glGetUniformuiv(FHandle, uniform.ID, @uniform.Data[0]);
            ctFloat : glGetUniformfv (FHandle, uniform.ID, @uniform.Data[0]);
            ctDouble: glGetUniformdv (FHandle, uniform.ID, @uniform.Data[0]);
        end;
        Begin
//          AllocConsole();
//          WriteLn(uniform.Name);
        end;
        FUniformList.Add(uniform.Name, uniform);
//        If FUniformList.Contains(uniform.Name) Then


        if uniform.DataClass = dcSampler then
        begin
          PInteger(@uniform.Data[0])^ := texIndex;
          glUniform1i(uniform.ID, texIndex);
          Inc(texIndex);
        end;
      end;
    end;

    glUseProgram(0);
  end;
end;

procedure TProgram.ReadAttributes;
var I, N: Integer;
    namebuf_ans: AnsiString;
    namebuf: string;
    attr : TAttributeField_OGL;
    writenlen: Integer;
    datasize: integer;
    datatype: Cardinal;
begin
  glGetProgramiv(FHandle, GL_ACTIVE_ATTRIBUTE_MAX_LENGTH, @N);
  if N > 0 then
  begin
    SetLength(namebuf_ans, N - 1);
    glGetProgramiv(FHandle, GL_ACTIVE_ATTRIBUTES, @N);
    for I := 0 to N - 1 do
    begin
      attr := TAttributeField_OGL.Create;

      FillChar(namebuf_ans[1], Length(namebuf_ans), 0);
      glGetActiveAttrib(FHandle, I, Length(namebuf_ans)+1, writenlen, datasize, datatype, @namebuf_ans[1]);
      namebuf := string(PAnsiChar(namebuf_ans));
      attr.Name := ReduceName(namebuf);
      attr.DataType := datatype;
      VectorInfoOfDataType(datatype, attr.DataClass, attr.ElementType, attr.ElementsCount);
      attr.ID := glGetAttribLocation(FHandle, @namebuf_ans[1]);

      FAttrList.Add(namebuf, attr);
    end;
  end;
end;

procedure TProgram.BindVAO(const AKey: TVAOKey);
var VAOInfo: TVAOInfo;
  function UpdateVAOBinding(Const AVAO: Cardinal): TVAOInfo;
  begin
    Result.VAO := AVAO;
    If Assigned(AKey.InstanceVertex) Then
    Begin
      glBindBuffer(GL_ARRAY_BUFFER, (AKey.InstanceVertex as IHandle).Handle);
      Result.Instance := AKey.InstanceVertex.Layout;
      SetAttributes(Result.Instance, AKey.InstanceStepRate);
    End
    Else
      Result.Instance := nil;

    If Assigned(AKey.ModelVertex) Then
    Begin
      glBindBuffer(GL_ARRAY_BUFFER, (AKey.ModelVertex as IHandle).Handle);
      Result.Model := AKey.ModelVertex.Layout;
      SetAttributes(Result.Model, 0);
    End
    Else
      Result.Model := nil;

    If Assigned(AKey.ModelIndex) Then
    Begin
      glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, (AKey.ModelIndex as IHandle).Handle);
      Result.HasIndices := True;
    End
    Else
      Result.HasIndices := False;
  end;
  function VAOInvalid(const VAOInfo: TVAOInfo): Boolean;
  begin
    if assigned(AKey.InstanceVertex) then
    begin
       Result := (VAOInfo.Instance <> AKey.InstanceVertex.Layout);
       if Result then Exit;
    end
    else
    begin
       Result := assigned(VAOInfo.Instance);
       if Result then Exit;
    end;

    if assigned(AKey.ModelVertex) then
    begin
       Result := (VAOInfo.Model <> AKey.ModelVertex.Layout);
       if Result then Exit;
    end
    else
    begin
       Result := assigned(VAOInfo.Model);
       if Result then Exit;
    end;

    if assigned(AKey.ModelIndex) then
    begin
      Result := Not VAOInfo.HasIndices;
      if Result then Exit;
    end
    else
      Result := VAOInfo.HasIndices;
  end;
begin
  {$IFDEF NOVAO}
  UpdateVAOBinding(0);
  {$ELSE}
  If not FVAOList.TryGetValue(AKey, VAOInfo) Then
  Begin
      glGenVertexArrays(1, @VAOInfo.VAO);
      glBindVertexArray(VAOInfo.VAO);
      VAOInfo := UpdateVAOBinding(VAOInfo.VAO);
      VAOInfo.BindTime := GetTickCount;
      FVAOList.Add(AKey, VAOInfo);
  End
  Else
  Begin
      glBindVertexArray(VAOInfo.VAO);
      If VAOInvalid(VAOInfo) Then
        VAOInfo := UpdateVAOBinding(VAOInfo.VAO);
      VAOInfo.BindTime := GetTickCount;
      FVAOList.Item[AKey] := VAOInfo;
  End;
  {$ENDIF}
end;

function TProgram.GetAttributeField(const name: string): TAttributeField_OGL;
begin
  if not FAttrList.TryGetValue(name, Result) then
    if not FAttrList.TryGetValue('in_'+name, Result) then
       if not FAttrList.TryGetValue('in_'+name+'0', Result) then
          Result := nil;
end;

procedure TProgram.SetAttribute(AttrField: TAttributeField_OGL;
  componentsCount, componentsType: integer; stride, offset: integer;
  divisor: Integer; normalized: Boolean);
begin
  if AttrField = nil then Exit;
  glEnableVertexAttribArray(AttrField.ID);
  glVertexAttribPointer(AttrField.ID, componentsCount, componentsType, normalized, stride, Pointer(offset));
  glVertexAttribDivisor(AttrField.ID, divisor);
end;

procedure TProgram.SetAttributes(const ALayout: IDataLayout; divisor: Integer);
var I: Integer;
begin
  if ALayout = nil then Exit;
  for I := 0 to ALayout.Count - 1 do
    SetAttribute(GetAttributeField(ALayout[I].Name),
                 ALayout[I].CompCount,
                 GLComponentType[ALayout[I].CompType],
                 ALayout.Size,
                 ALayout[I].Offset,
                 divisor,
                 ALayout[I].DoNorm);
end;

function TProgram.GetProgramInfoLog: string;
var n, dummy: Integer;
    astr: AnsiString;
begin
  Result := '';
  glGetProgramiv(Handle, GL_INFO_LOG_LENGTH, @n);
  if n > 1 then
  begin
    SetLength(astr, n-1);
    glGetProgramInfoLog(Handle, n, dummy, PAnsiChar(astr));
    Result := string(astr);
  end;
end;

procedure TProgram.ValidateProgram;
var param: GLuint;
begin
  if not FValidated then
  begin
    glValidateProgram(FHandle);
    glGetProgramiv(FHandle, GL_VALIDATE_STATUS, @param);
    if param<>1 then Raise3DError('Program validation failed: '+GetProgramInfoLog);
    FValidated := True;
  end;
end;

procedure TProgram.CleanUpUselessVAO;
var CurrTime, DTime: Cardinal;
    Key: TVAOKey;
    Value: TVAOInfo;
begin
  CurrTime := GetTickCount;
  FVAOList.Reset;
  while FVAOList.Next(Key, Value) do
  begin
    DTime := CurrTime - Value.BindTime;
    if DTime > 3000 then
    begin
      glDeleteVertexArrays(1, @Value.VAO);
      FVAOList.Delete(Key);
    end;
  end;
end;

procedure TProgram.AllocHandle;
begin
  FHandle := glCreateProgram();
end;

procedure TProgram.FreeHandle;
begin
  DetachAllShaders;
  glDeleteProgram(FHandle);
  FHandle := 0;
end;

procedure TProgram.Select;
begin
  glUseProgram(Handle);
end;

procedure TProgram.Load(const AProgram: string; FromResource: Boolean);
var stream: TStream;
    s: AnsiString;
    obj: ISuperObject;
    GLShader: Cardinal;
    param: integer;
begin
  stream := nil;
  try
    if FromResource then
    begin
      stream := TResourceStream.Create(HInstance, AProgram, RT_RCDATA);
    end
    else
    begin
      if FileExists(AProgram) then
        stream := TFileStream.Create(AProgram, fmOpenRead)
      else
      begin
        LogLn('File not found: ' + AProgram);
        Exit;
      end;
    end;
    SetLength(s, stream.Size);
    stream.Read(s[1], stream.Size);
  finally
    FreeAndNil(stream);
  end;

  obj := SO(s);
  DetachAllShaders;
  ClearUniformList;
  ClearAttrList;
  ClearVAOList;

  GLShader := CreateShader(AnsiString(obj.S['vertex']), stVertex);
  glAttachShader(FHandle, GLShader);
  GLShader := CreateShader(AnsiString(obj.S['fragment']), stFragment);
  glAttachShader(FHandle, GLShader);

  glLinkProgram(FHandle);
  glGetProgramiv(FHandle, GL_LINK_STATUS, @param);
  if param=1 then
  begin
    ReadUniforms;
    ReadAttributes;
  end;
end;

procedure TProgram.SetAttributes(const AModel, AInstances: IctxVetexBuffer;
  const AModelIndices: IctxIndexBuffer; InstanceStepRate: Integer = 1);
begin;
  FSelectedVAOKey.ModelVertex := AModel;
  FSelectedVAOKey.ModelIndex := AModelIndices;
  FSelectedVAOKey.InstanceVertex := AInstances;
  FSelectedVAOKey.InstanceStepRate :=InstanceStepRate;
  FSelectedVAOBinded := False;
end;

function TProgram.GetUniformField(const Name: string): TUniformField;
var value: TUniformField_OGL;
begin
  if FUniformList.TryGetValue(name, value) then
    Result := value
  else
    Result := nil;
end;

procedure TProgram.SetUniform(const Field: TUniformField; const Value: integer);
begin
  if Field = nil then Exit;
  if Field.DataClass = dcSampler then Exit;
  If value <> PInteger(Field.Data)^ then
  begin
    PInteger(Field.Data)^ := value;
    glUniform1i(TUniformField_OGL(Field).ID, value);
  end;
end;

procedure TProgram.SetUniform(const Field: TUniformField; const Value: single);
begin
  if Field = nil then Exit;
  if Field.DataClass = dcSampler then Exit;
  If PSingle(Field.Data)^ <> value then
  begin
    PSingle(Field.Data)^ := value;
    glUniform1f(TUniformField_OGL(Field).ID, value);
  end;
end;

procedure TProgram.SetUniform(const Field: TUniformField; const v: TVec2);
begin
  if Field = nil then Exit;
  if Field.DataClass = dcSampler then Exit;
  If PVec2(Field.Data)^ <> v Then
  begin
    PVec2(Field.Data)^ := v;
    glUniform2fv(TUniformField_OGL(Field).ID, 1, @v);
  end;
end;

procedure TProgram.SetUniform(const Field: TUniformField; const v: TVec3);
begin
  if Field = nil then Exit;
  if Field.DataClass = dcSampler then Exit;
  If PVec3(Field.Data)^ <> v Then
  begin
    PVec3(Field.Data)^ := v;
    glUniform3fv(TUniformField_OGL(Field).ID, 1, @v);
  end;
end;

procedure TProgram.SetUniform(const Field: TUniformField; const v: TVec4);
begin
  if Field = nil then Exit;
  if Field.DataClass = dcSampler then Exit;
  If PVec4(Field.Data)^ <> v Then
  begin
    PVec4(Field.Data)^ := v;
    glUniform4fv(TUniformField_OGL(Field).ID, 1, @v);
  end;
end;

procedure TProgram.SetUniform(const Field: TUniformField;
  const values: TSingleArr);
begin
  if Field = nil then Exit;
  if Field.DataClass = dcSampler then Exit;
  if Length(values) > 0 then
    if not CompareMem(@values[0], Field.Data, Length(values) * SizeOf(single)) then
    begin
      Move(values[0], Field.Data^, Length(values) * SizeOf(single));
      glUniform1fv(TUniformField_OGL(Field).ID, Length(values), @values[0]);
    end;
end;

procedure TProgram.SetUniform(const Field: TUniformField; const v: TVec4arr);
begin
  if Field = nil then Exit;
  if Field.DataClass = dcSampler then Exit;
  if Length(v) > 0 then
    if not CompareMem(@v[0], Field.Data, Length(v) * SizeOf(TVec4)) then
    begin
      Move(v[0], Field.Data^, Length(v) * SizeOf(TVec4));
      glUniform4fv(TUniformField_OGL(Field).ID, Length(v), @v[0]);
    end;
end;

procedure TProgram.SetUniform(const Field: TUniformField; const m: TMat4);
var mt: TMat4;
begin
  if Field = nil then Exit;
  if Field.DataClass = dcSampler then Exit;
  mt := Transpose(m);
  if not CompareMem(@mt, Field.Data, SizeOf(mt)) then
  begin
    Move(mt, Field.Data^, SizeOf(mt));
    glUniformMatrix4fv(TUniformField_OGL(Field).ID, 1, false, @mt);
  end;
end;

procedure TProgram.SetUniform(const Field: TUniformField; const tex: IctxTexture; const Sampler: TSamplerInfo);
//var gltex: ITextureHandle_OGL;
begin
{
  if Field = nil then Exit;
  if Field.DataClass <> dcSampler then Exit;
  if not Supports(tex, ITextureHandle_OGL, gltex) then Exit;
  gltex.Select(PInteger(Field.Data)^);
  glUniform1i(TOGLUniformField(Field).ID, PInteger(Field.Data)^);

  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GLMagTextureFilter[Sampler.MagFilter]);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GLMinTextureFilter[Sampler.MipFilter, Sampler.MinFilter]);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GLWrap[Sampler.Wrap_X]);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GLWrap[Sampler.Wrap_Y]);
  glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAX_ANISOTROPY_EXT, Sampler.Anisotropy);
}
end;

procedure TProgram.Draw(PrimTopology: TPrimitiveType; CullMode: TCullingMode;
  IndexedGeometry: Boolean; InstanceCount: Integer; Start: integer;
  Count: integer; BaseVertex: integer; BaseInstance: Integer);
var StrideSize: Integer;
    IndexSize: TIndexSize;
begin
  if not FSelectedVAOBinded then
  begin
    BindVAO(FSelectedVAOKey);
    FSelectedVAOBinded := True;
  end;

  ValidateProgram;
  FContext.States.CullMode := CullMode;

  if IndexedGeometry then
  begin
    IndexSize := FSelectedVAOKey.ModelIndex.IndexSize;
    if IndexSize = TIndexSize.DWord then
      StrideSize := 4
    else
      StrideSize := 2;
    Start := Start;
    Count := Count;
    if InstanceCount = 0 then
    begin
      if BaseVertex > 0 then
          glDrawElementsBaseVertex(GLPrimitiveType[PrimTopology], Count, GLIndexSize[IndexSize], Pointer(Start), BaseVertex)
      else
          glDrawElements(GLPrimitiveType[PrimTopology], Count, GLIndexSize[IndexSize], Pointer(Start));
    end
    else
    begin
      if BaseVertex > 0 then
      begin
          if BaseInstance > 0 then
              glDrawElementsInstancedBaseVertexBaseInstance(GLPrimitiveType[PrimTopology], Count, GLIndexSize[IndexSize], Pointer(Start), InstanceCount, BaseVertex, BaseInstance)
          else
              glDrawElementsInstancedBaseVertex(GLPrimitiveType[PrimTopology], Count, GLIndexSize[IndexSize], Pointer(Start), InstanceCount, BaseVertex);
      end
      else
      begin
          if BaseInstance > 0 then
              glDrawElementsInstancedBaseInstance(GLPrimitiveType[PrimTopology], Count, GLIndexSize[IndexSize], Pointer(Start), InstanceCount, BaseInstance)
          else
              glDrawElementsInstanced(GLPrimitiveType[PrimTopology], Count, GLIndexSize[IndexSize], Pointer(Start), InstanceCount);
      end;
    end;
  end
  else
  begin
    StrideSize := FSelectedVAOKey.ModelVertex.Layout.Size;
    Start := Start;
    Count := Count;
    if InstanceCount = 0 then
      glDrawArrays(GLPrimitiveType[PrimTopology], Start, Count)
    else
      if BaseInstance > 0 then
        glDrawArraysInstancedBaseInstance(GLPrimitiveType[PrimTopology], Start, Count, InstanceCount, BaseInstance)
      else
        glDrawArraysInstanced(GLPrimitiveType[PrimTopology], Start, Count, InstanceCount);
  end;
end;

constructor TProgram.Create(AContext: TContext_OGL);
var VaoKey: TVAOKey;
    VaoInfo: TVAOInfo;
begin
  inherited Create(AContext);
  FUniformList := TUniformHash.Create;
  FAttrList := TAttributeHash.Create;

  ZeroMemory(@VaoKey, SizeOf(VaoKey));
  ZeroMemory(@VaoInfo, SizeOf(VaoInfo));
  FVAOList := TVaoHash.Create(VaoKey, VaoInfo);
end;

destructor TProgram.Destroy;
begin
  ClearUniformList;
  ClearAttrList;
  ClearVAOList;
  DetachAllShaders;
  inherited Destroy;
end;

{ THandle }

function THandle.Handle: Cardinal;
begin
  Result := FHandle;
end;

function THandle.QueryInterface(constref iid: tguid; out obj): longint; stdcall;
begin
  if GetInterface(IID, obj) then
    Result := 0
  else
    Result := E_NOINTERFACE;
end;

function THandle._AddRef: longint; stdcall;
begin
  Result := InterLockedIncrement(FRefCount);
end;

function THandle._Release: longint; stdcall;
begin
  Result := InterlockedDecrement(FRefCount);
  if Result = 0 then
    if FContext.Binded then
      Free
    else
      FContext.AddHandlesForCleanup(Self);
end;

procedure THandle.AfterConstruction;
begin
  inherited AfterConstruction;
  InterLockedDecrement(FRefCount);
end;

constructor THandle.Create(AContext: TContext_OGL);
begin
  Assert(Assigned(AContext), 'Context can''t to be nil');
  Assert(AContext.Binded, 'Context can''t to be unbinded');
  FContext := AContext;
  FContext.AddHandle(Self);
  AllocHandle;
end;

class function THandle.NewInstance: TObject;
begin
  Result:=inherited NewInstance;
  THandle(Result).FRefCount := 1;
end;

destructor THandle.Destroy;
begin
  if Assigned(FContext) then
  begin
    FContext.RemoveHandle(Self);
    FreeHandle;
  end;
  inherited Destroy;
end;

{ TContext_OGL }

procedure TContext_OGL.AddHandle(const HandleObject: TObject);
begin
  FHandles.Add(HandleObject, True);
  if HandleObject is TProgram then
    FPrograms.Add(HandleObject);
end;

function TContext_OGL.GetActiveProgram: IctxProgram;
begin
  Result := FActiveProgram;
end;

procedure TContext_OGL.RemoveHandle(const HandleObject: TObject);
begin
  FHandles.Delete(HandleObject);
  if HandleObject is TProgram then
    FPrograms.Remove(HandleObject);
end;

procedure TContext_OGL.AddHandlesForCleanup(const HandleObject: TObject);
begin
  FDeletedHandles.Add(HandleObject);
end;

procedure TContext_OGL.CleanUpHandles;
var i: Integer;
begin
  for i := 0 to FDeletedHandles.Count - 1 do
    TObject(FDeletedHandles.Items[i]).Free;
  FDeletedHandles.Clear;
end;

procedure TContext_OGL.SetActiveProgram(AValue: IctxProgram);
begin
  if FActiveProgram = AValue then Exit;
  FActiveProgram := AValue;
end;

function TContext_OGL.CreateVertexBuffer: IctxVetexBuffer;
begin
  Result := TVertexBuffer.Create(Self);
end;

function TContext_OGL.CreateIndexBuffer: IctxIndexBuffer;
begin
  Result := TIndexBuffer.Create(Self);
end;

function TContext_OGL.CreateProgram: IctxProgram;
begin
  Result := TProgram.Create(Self);
end;

function TContext_OGL.CreateTexture: IctxTexture;
begin
  Result := TTexture.Create();
end;

function TContext_OGL.CreateFrameBuffer: IctxFrameBuffer;
begin

end;

function TContext_OGL.States: IRenderStates;
begin
  Result := FStatesIntf;
end;

function TContext_OGL.Binded: Boolean;
begin
  Result := FBindCount > 0;
end;

function TContext_OGL.Bind: Boolean;
begin
  if FBindCount = 0 then
    wglMakeCurrent(FDC, FRC);
  Inc(FBindCount);
  Result := True;
end;

function TContext_OGL.Unbind: Boolean;
begin
  Dec(FBindCount);
  if FBindCount = 0 then
  begin
    wglMakeCurrent(0, 0);
    glUseProgram(0);
    FActiveProgram := nil;
  end;
  Result := True;
end;
procedure TContext_OGL.Clear(const color  : TVec4;      doColor  : Boolean = True;
                                   depth  : Single = 1; doDepth  : Boolean = False;
                                   stencil: Byte   = 0; doStencil: Boolean = False);
begin
  glClearColor(color.x, color.y, color.z, color.w);
  glClear(GL_COLOR_BUFFER_BIT);
end;

procedure TContext_OGL.Present;
begin
  SwapBuffers(FDC);
end;

constructor TContext_OGL.Create(const Wnd: TWindow);
begin
  FWnd := Wnd;
  FDC := GetDC(FWnd);
  FRC := CreateRenderingContext(FDC, [], 32, 0, 0, 0, 0, 0);
  ActivateRenderingContext(FDC, FRC);
  DeactivateRenderingContext;

  FHandles := TObjListHash.Create;
  FPrograms := TList.Create;
  FDeletedHandles := TList.Create;

  FStates := TStates_OGL.Create(Self);
  FStatesIntf := TStates_OGL(FStates);
end;

destructor TContext_OGL.Destroy;
begin
  FreeAndNil(FDeletedHandles);
  FreeAndNil(FPrograms);
  FStatesIntf := nil;
  FreeAndNil(FStates);
  inherited Destroy;
end;

end.
