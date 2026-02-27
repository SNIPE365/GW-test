#define __Main Alright
#include "windows.bi"

#include "..\loader\modules\Initgl.bas"

var hWnd = InitOpenGL()

ResizeOpengGL(800,600)

glDisable( GL_LIGHTING )

do
    
  printf(".")
  
  glClearColor rnd/8,rnd/8,rnd/8,1
  glClear GL_COLOR_BUFFER_BIT OR GL_DEPTH_BUFFER_BIT      
  glLoadIdentity()
  
  glTranslatef( -5 , -5 , -50 )     
  glColor3f( 1 , .5 , .25 )
  glutSolidSphere( 6 , 18 , 7 ) 'male round (.5,.5,N\2)
  
  flip
  
loop until len(inkey)