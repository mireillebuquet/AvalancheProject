   D X _ b a s e . h l s l Є"  DXBC)"я]Рy╞uV╪=Nyв   Є"     8   д  °  L  м  (  RDEFd     H          ■ С  1  <                              $Globals ллл<      `              А      @       М      Ь  @   @       М      з  А   @       М      ▒  └   @       М      ║     @       М      ╩  @  @       М      ▄  А  @       М      э  └  @       М      ¤     @      М        @  @       М        А  @      М      !  └  @       М      M_Matrix ллл            MVP_Matrix MV_Matrix P_Matrix M_InverseMatrix MVP_InverseMatrix MV_InverseMatrix P_InverseMatrix VP_Matrix VP_InverseMatrix V_Matrix V_InverseMatrix Microsoft (R) HLSL Shader Compiler 9.29.952.3111 ллISGNL         8                    @                   vsCoord vsNormal лллOSGNL         8                    D                   SV_Position Normal лSHDRX  @  V   Y  FО      +   _  r     _  r    g  Є         e  r     h     8  Є      V     FО      !   2  
Є      FО               F     2  
Є      FО      "   ж     F        Є      F     FО      #   8  r      V    FВ      )   2  
r      FВ      (       F     2  
r     FВ      *   ж    F     >  STATt                                                                                                                  SDBG┬  T   s  д  з  С               -   p     и     Р     Ш       T  └      S   S   ╤      8                                             А     А   А                      А     А   А                      А     А   А                      А     А   А                                                                                                                                                                                                             X      P      2                                             А     А   А                     А     А   А                     А     А   А                     А     А   А                                                                                                                                                                                                            X      P      2                                             А     А   А                     А     А   А                     А     А   А                     А     А   А                                                                                                                                                                                                            X      P                                     &              А     А   А      '              А     А   А      (              А     А   А      )              А     А   А                                                                                                                                                                                                            X              8                                              А     А   А                      А     А   А                      А     А   А                                                                                                                                                                                                                                                 X      d      2                                              А     А   А                     А     А   А                     А     А   А                                                                                                                                                                                                                                                X      d      2                              *              А     А   А      +              А     А   А      ,              А     А   А                                                                                                                                                                                                                                                X      d      >                                                                                                                                                                                                                                                                                                                                                                                         X                                                                                                                                                                                                                 	                    
                                                                                                                     
                     
                    
                    
                    
                    
                    
                    
                    
                    
   	                 
   
                 
                    
                    
                    
                    
                                                                                                                                                                                                                                                                                                    !                      "                      #                      $                     %                                                                                                                     !                     !          	          !                    !                    "                     "          
          "                    "                    #                     #                    #                    #                    (                     (                    (                    )                     )                    )                    *                     *                    *                       1               B         	      Д          	   
   Ш          	   	   о          	      Ъ          	      ╫          	      Є       	   	            
   	      Ї          	   	   Щ          	      є          	      п          	               
      ┐               T               b               ┘                B                ┘          
      ┐         	   	   Щ          	      п                                                            ┐                 	             $                	            +        D      ┐        H                                                                                                                                                                                                                                                                                    	                                       
                                                                                                                                                                                                                                                                                                                                                            &                                                                                                                              	   
                                 
      C:\MyProj\AvalancheProject\Demos\Src\Texturing\Texturing_shaders\!Out\DX_base_v.cpp#ifndef MATRICES_H
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
GlobalsLocalsVS_Input::vsCoordVS_Input::vsNormalVS_Output::PosVS_Output::NormalMicrosoft (R) HLSL Shader Compiler 9.29.952.3111 VS vs_4_0     ┌  DXBC▒°┐нc)╩anf╞гtr   ┌     8   Р   ф     ─  @  RDEFP                     С     Microsoft (R) HLSL Shader Compiler 9.29.952.3111 лллISGNL         8                    D                   SV_Position Normal лOSGN,                               SV_Target ллSHDRд   @   )   b r    e  Є      h             F    F    D        
      8        
      *    4  Є       АA       @                  >  STATt                                                                                                                  SDBGТ  T   з  ╪  █  С                  ╠     ь     4	     8
     ╪
    \      S   S                                                         А         А                                                                                                                                                                                                                                                                                                              
          0              D                                                А                                                                                                                                                                                                                                                                                                                        
          0              8                                               А     А   А                                                                                                                                                                                                                                                                                                              
          0      <      4                                            А      А  А                     А      А  А       	              А      А  А       
              А      А  А                                                                                                                                                                                                             D              >                                                                                                                                                                                                                                                                                                                                                                                         D                                                                                                                                                                                                                                         	                                                                                                 z               З         
      \                Ч               _                B                                _          
      \                                                                            \                п   	             m              п   	            t              \               t              \         $                                                                                                                                                                                                                                                                                                                                                       C:\MyProj\AvalancheProject\Demos\Src\Texturing\Texturing_shaders\!Out\DX_base_f.cpp
struct PS_Input {
    float4 Pos   : POSITION;
    float3 Normal: Normal;
};

struct PS_Output {
    float4 Color : COLOR;
};

PS_Output PS(PS_Input In) {
    PS_Output Out;
    float3 n = normalize(In.Normal);    
    Out.Color = max(0.0, -n.z);
    return Out;
}
GlobalsLocalsPS_Input::PosPS_Input::NormalPS_Output::ColorMicrosoft (R) HLSL Shader Compiler 9.29.952.3111 PS ps_4_0 