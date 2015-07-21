#ifndef MATRICES_H
#define	MATRICES_H
float4x4 M_Matrix;
float4x4 MVP_Matrix;
float4x4 MV_Matrix;
float4x4 P_Matrix;
float4x4 M_InverseMatrix;
float4x4 MVP_InverseMatrix;
float4x4 MV_InverseMatrix;
float4x4 P_InverseMatrix;
float4x4 VP_Matrix;
float4x4 VP_InverseMatrix;
float4x4 V_Matrix;
float4x4 V_InverseMatrix;
#endif	/* MATRICES_H */

struct VS_Input {
    float3 vsCoord : vsCoord;
    float3 vsNormal: vsNormal;
};

struct VS_Output {
    float4 Pos   : POSITION;
    float3 Normal: Normal;
};

VS_Output VS(VS_Input In) {
    VS_Output Out;
    Out.Pos = mul(VP_Matrix, float4(In.vsCoord, 1.0));    
    Out.Normal = mul(V_Matrix, float4(In.vsNormal, 0.0)).xyz;
    return Out;
}