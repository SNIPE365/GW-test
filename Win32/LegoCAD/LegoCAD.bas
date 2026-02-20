#define __Main "LegoCAD"

#define _WIN32_WINNT &h0600
#include once "windows.bi"
#include once "win\commctrl.bi"
#include once "win\commdlg.bi"
#include once "win\cderr.bi"
#include once "win\ole2.bi"
#include once "win\Richedit.bi"
#include once "win\uxtheme.bi"
#include once "win\shlwapi.bi"
#include once "crt.bi"
#include once "fbthread.bi"

#define Errorf(p...)
#define Debugf(p...)

enum StatusParts
   spStatus
   spCursor
end enum
enum WindowControls
  wcMain
  wcBtnClose
  wcSidePanel
  
  wcSideSplit
  wcBtnSide
  wcGraphic  
  wcStatus
  wcLast
end enum
enum WindowFonts
   wfDefault
   wfEdit
   wfStatus
   wfSmall
   wfArrows
   wfLast
end enum
enum Accelerators
   acFirst = 9100-1
   'acToggleMenu   
   'acFilterDump
end enum

#define CTL(_I) g_tMainCtx.hCtl(_I).hwnd
#define AsBool(_var) cast(boolean,((_var)<>0))

'dim shared as boolean g_bChangingFont = false

'#include Once "LSModules\ColoredButtons.bas"
#include once "..\LSModules\TryCatch.bas"
#include once "..\LSModules\Layout.bas"

type FormContext
  as FormStruct        tForm        'Form structure
  as ControlStruct     hCTL(wcLast) 'controls
  as FontStruct        hFnt(wfLast) 'fonts  
end type
type TabStruct
   hEdit      as hwnd
   sFilename  as string
   iLinked    as long   = -1
end type

'redim shared g_tTabs(0) as TabStruct 
'dim shared as long g_iTabCount = 1 , g_iCurTab = 0

const g_sMainFont  = "verdana" , g_sFixedFont = "consolas" , g_sArrowFont = "Webdings"

dim shared as FormContext g_tMainCtx
dim shared as hinstance g_AppInstance  'instance
dim shared as string sAppName        'AppName (window title 'prefix')
dim shared as HMENU g_WndMenu        'Main Menu handle
'dim shared as long g_WndWid=640 , g_WndHei=480
dim shared g_hCurMenu as any ptr , g_CurItemID as long , g_CurItemState as long
dim shared as HANDLE g_hResizeEvent
dim shared as hwnd g_GfxHwnd
dim shared as byte g_DoQuit
dim shared as any ptr g_ViewerThread
dim shared as string g_CurrentFilePath

type LegoCadConfig
  'as long lGfxX,lGfxY,lGfxWid,lGfxHei
  as long lGuiWid,lGuiHei
end type
static shared g_tCfg as LegoCadConfig
with g_tCfg
  .lGuiWid=640 : .lGuiHei = 480
  '.lGfxWid=640 : .lGfxHei = 480
end with
  

#include "..\Loader\Modules\Matrix.bas"
#include "..\Loader\LoadLDR.bas"
'#include once "..\LSModules\Settings.bas"
#include "..\Loader\Include\Colours.bas"
#include "..\Loader\Modules\Clipboard.bas"
#include "..\Loader\Modules\InitGL.bas"
#include "..\Loader\Modules\Math3D.bas"
#include "..\Loader\Modules\Normals.bas"
#include "..\Loader\Modules\Model.bas"

sub LogError( sError as string )   
   var f = freefile()
   open exepath+"\FatalErrors.log" for append as #f
   print #f, date() + " " + time() + sError
   close #f   
   puts(sError)
   SetWindowText( CTL(wcStatus) , sError )   
   MessageBox( CTL(wcMain) , sError , NULL , MB_ICONERROR )
end sub

'#include "LsModules\LSMenu.bas"
#include "..\LsModules\LSViewer.bas"
'#include "LSModules\LSActions.bas"

#if 0
  sub ProcessAccelerator( iID as long )
     select case iID
     case acToggleMenu
        SetMenu( CTL(wcMain) , iif( GetMenu(CTL(wcMain)) , NULL , g_WndMenu ) )
     case meFirst+1 to MeLast-1 '--- accelerators for menu's as well ---
        Menu.Trigger( iID )
     case acFilterDump        : puts("Dump filter parts")  '--- debug accelerators ---
     end select
  end sub
  function CreateMainAccelerators() as HACCEL
     '#macro ForEachMenuEntry( __Entry , __SubMenu , __EndSubMenu , __Separator )
     #define __Dummy( _Dummy... ) __FB_UNQUOTE__("_")
     ''#macro _Entry( _idName , _Unused0 , _Modifiers , _Accelerator , _Unused... )            
     ''   __FB_UNQUOTE__( __FB_EVAL__( __FB_IIF__( __FB_ARG_COUNT__(_Accelerator) , "( " __FB_QUOTE__( __FB_EVAL__(_Modifiers)) " or FVIRTKEY , " #_Accelerator ", " #_idName " ), _ " , "_ " ) ) )      
     ''#endmacro
     static as ACCEL AccelList(...) = { _
        ForEachMenuEntry( _Entry , __Dummy , __Dummy , __Dummy )
        ( FSHIFT or FVIRTKEY , VK_SPACE , acToggleMenu ) _
     }
     return CreateAcceleratorTable( @AccelList(0) , ubound(AccelList)+1 )
  end function
#endif

sub ResizeMainWindow( bInit as boolean = false )            
  static as boolean bResize   
  if bResize then exit sub    
  'Calculate Client Area Size
  dim as RECT RcWnd=any,RcCli=any,RcDesk=any
      
  var hWnd = CTL(wcMain)
  if hWnd=0 orelse IsIconic(hWnd) orelse (bInit=0 andalso IsWindowVisible(hWnd)=0) then exit sub   
  bResize = true : GetClientRect(hWnd,@RcCli)
  GetWindowRect(hWnd,@RcWnd) 
  'Window Rect is in SCREEN coordinate.... make right/bottom become WID/HEI
  if 1 then 'bInit orelse (RcCli.right<>g_tCfg.lGuiWid) orelse (RcCli.bottom<>g_tCfg.lGuiHei) then
    with RcWnd      
      .right -= .left : .bottom -= .top                   'get window size
      .right -= RcCli.right : .bottom -= RcCli.bottom      'make it be difference from wnd/client
      .right += g_tCfg.lGuiWid : .bottom += g_tCfg.lGuiHei 'add back desired client area size
      GetClientRect(GetDesktopWindow(),@RcDesk)         
      
      'if using default settings then center the window
      if bInit andalso true then ''g_tCfg.lGuiX = clng(CW_USEDEFAULT) then
        var iCenterX = (RcDesk.right-.right)\2 , iCenterY = (RcDesk.bottom-.bottom)\2                 
        SetWindowPos(hwnd,null,iCenterX,iCenterY,.right,.bottom,SWP_NOZORDER or SWP_NOSENDCHANGING)
      else            
        'SetWindowPos(hwnd,null,.left,.top,.right,.bottom,SWP_NOZORDER or SWP_NOSENDCHANGING)                     
      end if
      'puts("Wid: " & g_tCfg.lGuiWid & " Hei: " & g_tCfg.lGuiHei )
      'GetClientRect( hWnd , @RcCli )
      'puts("Wid?: " & RcCli.right & " Hei?: " & RcCli.bottom )
    end with   
  end if
  RcCli.right = g_tCfg.lGuiWid : RcCli.bottom = g_tCfg.lGuiHei
  
  'trigger a window maximizing if settings says so.
  if bInit andalso 0 then '' g_tCfg.bGuiMaximized then
    PostMessage( hWnd , WM_SYSCOMMAND , SC_MAXIMIZE,0 )
  end if
  
  'recalculate control sizes based on window size
  ''if g_hContainer then ShowWindow( g_hContainer , SW_HIDE )      
  ''var iModify = SendMessage( CTL(wcEdit) , EM_GETMODIFY , 0 , 0 )   
  
  SendMessage( hWnd , WM_USER+80 , RcCli.right,RcCli.bottom )
  'ResizeLayout( hWnd , g_tMainCtx.tForm , RcCli.right , RcCli.bottom )
  
  ''UpdateTabCloseButton() 
  ''SendMessage( CTL(wcEdit) , EM_SETMODIFY , iModify , 0 )
    
  'if g_hSearch andalso g_hContainer then UpdateSearchWindowFont( g_tMainCtx.hFnt(wfStatus).HFONT )      
  MoveWindow( CTL(wcStatus) ,0,0 , 0,0 , TRUE )
  dim as long aWidths(2-1) = {RcCli.right*.85,-1}
  SendMessage( CTL(wcStatus) , SB_SETPARTS , 2 , cast(LPARAM,@aWidths(0)) )
  
  'DockGfxWindow()   
  bResize=false   
  'puts("...")
end sub
function SplitterWndProc( hWnd as HWND, message as UINT, wParam as WPARAM, lParam as LPARAM ) as LRESULT
  const waLocked = 0 , waHorizontal = 2 , waPosition = 4
  
  static as HCURSOR hHorz,hVert
  select case message
  case WM_SETCURSOR
    SetCursor( iif( GetWindowWord( hWnd , waHorizontal ) , hHorz , hVert ) )
  case WM_MOUSEMOVE
    if GetWindowWord( hWnd , waLocked ) then
      var hParent = GetParent( hWnd )
      dim as POINT myPT = type( cshort(LOWORD(lParam)) , cshort(HIWORD(lParam)) )
      MapWindowPoints( hWnd , hParent , @MyPT , 1 )      
      var iPos = iif( GetWindowWord( hWnd , waHorizontal ) , MyPT.x , MyPT.y )
      if GetWindowLong( hWnd , waPosition ) <> iPos then
        SetWindowLong( hWnd , waPosition , iPos )
        dim as NMHDR tHDR
        with tHDR
          .hwndFrom = hWnd
          .idFrom   = GetWindowLong( hWnd , GWL_ID )
          .code     = GetWindowLong( hWnd , waPosition )
        end with
        SendMessage( hParent , WM_NOTIFY , tHDR.idFrom , cast(LPARAM, @tHDR) )        
      end if
    end if
  case WM_SIZE
    _ContinueOnSize:
    dim as RECT tRC = any : GetClientRect( hWnd , @tRC )
    SetWindowWord( hWnd , waHorizontal , (tRC.bottom > tRC.right) )
  case WM_LBUTTONDOWN
    SetWindowWord( hWnd , waLocked , 1 )
    SetCapture( hWnd )    
  case WM_LBUTTONUP, WM_CAPTURECHANGED  
    _ContinueOnButtonUp:
    if GetWindowWord( hWnd , waLocked ) then 
      SetWindowWord( hWnd , waLocked , 0 )
      ReleaseCapture()
    end if
  case WM_CREATE
    if message = WM_CREATE then
      hHorz = LoadCursor( NULL , IDC_SIZEWE )
      hVert = LoadCursor( NULL , IDC_SIZENS )
    end if
    SetWindowWord( hWnd , waLocked , 0 )
    goto _ContinueOnSize  
  case WM_DESTROY
    'KillTimer( hWnd , 1 )
    DestroyCursor( hHorz ) : hHorz = 0
    DestroyCursor( hVert ) : hVert = 0
    goto _ContinueOnButtonUp
  end select
  
  return DefWindowProc( hWnd , message , wParam , lParam )
end function

function WndProc ( hWnd as HWND, message as UINT, wParam as WPARAM, lParam as LPARAM ) as LRESULT
    
  var pCtx = (@g_tMainCtx)      
  #include "..\LSModules\Controls.bas"
  #include "..\LSModules\ControlsMacros.bas"  
  
  select case( message )    
  case WM_CTLCOLOREDIT
    var hDC = cast(HDC,wParam), hCtl = cast(HWND,lParam)
    #if 0
      select case hCtl      
      case CTL(wcSearchEdit),CTL(wcFilterEdit)
        if GetWindowTextLength(hCtl)=0 then
          dim as zstring ptr pzText
          select case hCtl
          case CTL(wcSearchEdit) : pzText = @"Search..."
          case CTL(wcFilterEdit) : pzText = @"Filter..."
          end select
          dim as RECT tRC = any : GetClientRect(hCtl,@tRC)
          var iC = ((GetSysColor( COLOR_GRAYTEXT ) and &hFEFEFE) shr 1)+&h808080
          SetTextColor( hDC , iC )
          SetBkColor( hDC , GetSysColor(COLOR_WINDOW) )
          ExtTextOut( hDC , tRc.left , tRc.top , ETO_CLIPPED or ETO_OPAQUE , @tRc , pzText , 9  , NULL )
          return cast(LRESULT,GetStockObject(NULL_BRUSH))
        end if
      end select
    #endif
  case WM_NOTIFY     'notification from window/control
    var wID = cast(long,wParam) , pnmh = cptr(LPNMHDR,lParam)    
    select case wID    
    case wcSideSplit      
      if SendMessage( CTL(wcBtnSide) , BM_GETCHECK , 0 , 0 )=0 then 
        SendMessage( CTL(wcBtnSide) , BM_CLICK , 0,0 )
        SendMessage( pnmh->hwndFrom , WM_LBUTTONDOWN , 0,0 )
      end if
      var hWnd = CTL(wcMain)
      dim as long iX = pnmh->code
      dim as RECT RcCli=any : GetClientRect(hWnd,@RcCli)
      with g_tMainCtx.hCTL( wcSidePanel )
        var iWid = iX-.iX , iMinWid = g_tMainCtx.tForm.pCtl[wcBtnSide].iW
        var iMaxWid = (RcCli.Right-.iX)-iMinWid
        if iWid < iMinWid then iWid = iMinWid
        if iWid > iMaxWid then iWid = iMaxWid
        .tW = _Pct( (iWid*100)/RcCli.Right )
      end with  
      PostMessage( hWnd , WM_USER+80 , RcCli.right , RcCli.bottom )
      'ResizeLayout( hWnd , g_tMainCtx.tForm , RcCli.right , RcCli.bottom )      
    #if 0
      case wcOutSplit            
        if SendMessage( CTL(wcBtnMinOut) , BM_GETCHECK , 0 , 0 )=0 then 
          SendMessage( CTL(wcBtnMinOut) , BM_CLICK , 0,0 )
          SendMessage( pnmh->hwndFrom , WM_LBUTTONDOWN , 0,0 )
        end if
        var hWnd = CTL(wcMain)
        dim as long iY = pnmh->code        
        dim as RECT RcCli=any : GetClientRect(hWnd,@RcCli)
        'printf("%i ",iY)
        ''g_tMainCtx.hCTL( wID-1 ).tW = iif(iOpen, _Pct(20) , _Pct(0))     
        with g_tMainCtx.hCTL( wID-1 )
          var iHei = iY-.iY , iMinHei = g_tMainCtx.tForm.pCtl[wcButton].iH
          var iMaxHei = (RcCli.Bottom-.iY)-(iMinHei*2)
          if iHei < iMinHei then iHei = iMinHei
          if iHei > iMaxHei then iHei = iMaxHei
          .tH = _Pct( (iHei*100)/RcCli.Bottom )
        end with        
        ResizeLayout( hWnd , g_tMainCtx.tForm , RcCli.right , RcCli.bottom )
      case wcTabs
         select case pnmh->code
         case TCN_SELCHANGE
            var iIDX = TabCtrl_GetCurSel( CTL(wID) )            
            ChangeToTab( iIDX , true )
         end select
      case wcEdit
         select case pnmh->code                  
         case EN_SELCHANGE
            if g_bChangingFont then return 0
            with *cptr(SELCHANGE ptr,lParam)
               'static as CHARRANGE tPrev = type(-1,-2)
               'if memcmp( @.chrg , tPrev , sizeof(tPrev))CHARRANGE
               var iRow = SendMessage( CTL(wID) , EM_EXLINEFROMCHAR , 0 , .chrg.cpMax )
               var iCol = .chrg.cpMax - SendMessage( CTL(wID) , EM_LINEINDEX  , iRow , 0 )
               dim as zstring*64 zPart = any : sprintf(zPart,"%i : %i",iRow+1,iCol+1)
               'printf(!"(%s) > %i to %i    \r",,,.chrg.cpMin,.chrg.cpMax)
               SendMessage( CTL(wcStatus) , SB_SETTEXT , spCursor , cast(LPARAM,@zPart) ) 
               if cuint((.chrg.cpmax-.chrg.cpMin)-1) < 20 then
                  EnableWindow( CTL(wcBtnInc) , true )
                  EnableWindow( CTL(wcBtnDec) , true )
               else
                  EnableWindow( CTL(wcBtnInc) , false )
                  EnableWindow( CTL(wcBtnDec) , false )
               end if
               RichEdit_TopRowChange( CTL(wID) )
               RichEdit_SelChange( CTL(wID) , iRow , iCol )
            end with
         end select
      case wcSearchList
        puts("???")    
    #endif
    end select
    return 0
  case WM_COMMAND    'Event happened to a control (child window)
    var wNotifyCode = cint(HIWORD(wParam)), wID = LOWORD(wParam) , hwndCtl = cast(.HWND,lParam)      
    if hwndCtl=0 andalso wNotifyCode=0 then wNotifyCode = -1      
    if hwndCtl=0 andalso wNotifyCode=1 then wNotifyCode = -2
    
    #if 0
      select case wNotifyCode
      case -1         'Command from Menu
         if wID <> g_CurItemID then return 0 'not valid menu event
         dim as MENUITEMINFO tItem = type( sizeof(MENUITEMINFO) , MIIM_DATA or MIIM_STATE )  
         GetMenuItemInfo( g_hCurMenu , wID , false , @tItem )
         g_CurItemState = tItem.fState
         if tItem.dwItemData then
           dim MenuItemCallback as sub () = cast(any ptr,tItem.dwItemData)
           MenuItemCallback()        
         end if
         g_CurItemID = 0 : g_hCurMenu = 0 : return 0
      case -2         'Accelerator
         ProcessAccelerator( wID )
         return 0
      case BN_CLICKED 'Clicked action for different buttons
         select case wID
         case wcBtnClose  : File_Close()
         case wcButton    : Button_Compile()
         case wcBtnDec    : RichEdit_IncDec( CTL(wcEdit) , false )
         case wcBtnInc    : RichEdit_IncDec( CTL(wcEdit) , true )
         case wcRadOutput : Output_SetMode()
         case wcRadQuery  : Output_SetMode()
         case wcBtnExec   : Output_QueryExecute()
         case wcBtnLoad   : Output_Load()
         case wcBtnSave   : Output_Save()
         case wcBtnMinOut : Output_ShowHide()
         case wcBtnSide   : Solution_ShowHide()
         end select
      case BN_DBLCLK  'double clicked in rapid fire buttons
        select case wID
        case wcBtnDec    : RichEdit_IncDec( CTL(wcEdit) , false )
        case wcBtnInc    : RichEdit_IncDec( CTL(wcEdit) , true )
        end select    
      end select
    #endif
    
    return 0
  
  case WM_SIZE       'window is sizing/was sized
    if wParam <> SIZE_MINIMIZED andalso wParam <> SIZE_MAXHIDE then 
       var lWid = clng(LOWORD(lParam)) , lHei = clng(HIWORD(lParam))       
       if g_tCfg.lGuiWid <> lWid orelse g_tCfg.lGuiHei <> lHei then
        g_tCfg.lGuiWid = lWid : g_tCfg.lGuiHei = lHei
        ResizeMainWindow() '': UpdateTabCloseButton() 
       end if         
       return 0
    end if
  case WM_MOVE       'window is moving/was moved
    'DockGfxWindow()
  case WM_ERASEBKGND    
    return 1  
  case WM_PAINT    
    dim as PAINTSTRUCT tPaint    
    BeginPaint( hWnd , @tPaint )        
    PostMessage( hwnd , WM_USER+4 , 0 , 0 )    
    EndPaint( hWnd , @tPaint )    
    return 0
  case WM_USER+1 'gfx resized
    SetEvent(g_hResizeEvent)
    'DockGfxWindow()
    return 0
  case WM_USER+4 'late erase bkgnd
    UpdateWindow(hwnd)
    dim as RECT rc = any: GetClientRect( hwnd , @rc )    
    var hdc = GetDC(hwnd) , rgn = CreateRectRgnIndirect(@rc)
    var child = GetWindow(hwnd, GW_CHILD)
    while (child)
      dim as RECT cr = any
      if (IsWindowVisible(child)) then
        GetWindowRect(child, @cr)
        MapWindowPoints(NULL, hwnd, cast(POINT ptr,@cr), 2)
        var crgn = CreateRectRgnIndirect(@cr)
        CombineRgn(rgn, rgn, crgn, RGN_DIFF)
        DeleteObject(crgn)
      end if
      child = GetNextWindow(child, GW_HWNDNEXT)
    wend

    SelectClipRgn(hdc, rgn)
    FillRect( hDC , @rc , cast(HBRUSH,GetClassLong( hwnd , GCL_HBRBACKGROUND)) )
    SelectClipRgn(hdc, NULL)
    DeleteObject(rgn)
    ReleaseDC(hwnd, hdc)
    
    return 0
  case WM_USER+80 'InvalidateRect( hWnd , NULL , TRUE )
    dim as RECT RcCli=any 
    if wParam then
      RcCli.right = wParam : RcCli.bottom = lParam 
    else
      GetClientRect(hWnd,@RcCli)
    end if
    ResizeLayout( hWnd , g_tMainCtx.tForm , RcCli.right , RcCli.bottom )
    var iW = g_tMainCtx.tForm.pCtl[wcGraphic].iW
    var iH = g_tMainCtx.tForm.pCtl[wcGraphic].iH        
    SetWindowPos( g_GfxHwnd , 0 , 0,0 , iW,iH , SWP_NOZORDER or SWP_NOACTIVATE )    
  case WM_MENUSELECT 'track newest menu handle/item/state
    var iID = cuint(LOWORD(wParam)) , fuFlags = cuint(HIWORD(wParam)) , hMenu = cast(HMENU,lParam) 
    if hMenu then g_CurItemID = iID : g_hCurMenu = hMenu            
    return 0
  case WM_ACTIVATE  'Activated/Deactivated
    #if 0
    static as boolean b_IgnoreActivation      
    if b_IgnoreActivation=false andalso AsBool(g_GfxHwnd) andalso g_Show3D then
       var fActive = LOWORD(wParam) , fMinimized = HIWORD(wParam) , hwndPrevious = cast(HWND,lParam)
       if fActive then            
          'puts("Main Activate")
          SetWindowPos( g_GfxHwnd , HWND_TOPMOST , 0,0,0,0 , SWP_NOMOVE or SWP_NOSIZE or SWP_NOACTIVATE)
          DockGfxWindow()
          SetWindowPos( g_GfxHwnd , HWND_NOTOPMOST , 0,0,0,0 , SWP_NOMOVE or SWP_NOSIZE or SWP_NOACTIVATE or SWP_SHOWWINDOW)            
          'SetFocus( CTL(wcMain) )
       else
          'puts("main deactivate")
          if isIconic(g_GfxHwnd) = 0 then            
             if fMinimized andalso (GetKeyState(VK_SHIFT) shr 7) then                              
                ShowWindow( g_GfxHwnd , SW_HIDE )
             else
                SetWindowPos( g_GfxHwnd , HWND_NOTOPMOST , 0,0 , 0,0 , SWP_NOMOVE or SWP_NOSIZE or SWP_NOACTIVATE )                  
                
             end if
          end if
       end if
    end if   
    #endif
  case WM_DROPFILES
    #if 0
      var hDrop = cast(HANDLE,wParam)
      if wParam=0 then return 0
      var iFiles = DragQueryFile( hDrop , &hFFFFFFFF , NULL , 0 )
      if iFiles > 9 then
        var iResu = MessageBox( hwnd , "You're opening " & iFiles & " files, want to continue?" , sAppName , MB_ICONINFORMATION or MB_TASKMODAL or MB_YESNO )
        if iResu = IDNO then iFiles=0
      end if
      for N as long = 0 to iFiles-1
        dim as zstring*65536 zFile = any
        if DragQueryFile( hDrop , N , zFile , 65535 ) then LoadScript( zFile )
      next N  
      DragFinish( hDrop )
      return 1
    #endif
  case WM_ENTERMENULOOP , WM_ENTERSIZEMOVE  
   'ShowWindow( g_hContainer , SW_HIDE )
  case WM_CREATE  'Window was created
    #include "Modules\MainCreate.bas"          
    var sCurDir = curdir()+"\"
    
    #if 0
    for N as long = 1 to ubound(g_sOpenFiles)
       var sFile = g_sOpenFiles(N)
       if len(sFile)=0 then exit for
       for N as long = 0 to len(sFile)
          if sFile[N] = asc("/") then sFile[N] = asc("\")
       next N
       if FileExists(sCurDir+sFile) then 
          sFile = sCurDir + sFile
       elseif FileExists(sFile)=0 then
          var iResu = MessageBox( CTL(wcMain) , _
             !"File does not exist: \r\n\r\n" _
             !"'"+sFile+!"'\r\n\r\n" _
             !"Create it?", NULL , MB_ICONERROR or MB_YESNOCANCEL )
          if iResu = IDCANCEL then exit for
          if iResu = IDNO then continue for            
          sFile = ":"+sFile
       end if      
       'puts(sFile)
       var pzTemp = cptr(zstring ptr,malloc(65536))
       PathCanonicalizeA( pzTemp , sFile )
       LoadScript( *pzTemp )
       free(pzTemp)
    next N
    #endif
    
    return 0
  case WM_CLOSE   'close button was clicked
    #if 0
      if File_Quit()=false then return 0      
      'puts("" & IsWindow( CTL(wcEdit) ) & " // " & IsWindow( CTL(wcLines) ))
      if OrgEditProc then          
         var pOrgProc = OrgEditProc : OrgEditProc = @DefWindowProc         
         SetWindowLongPtr( CTL(wcEdit) , GWLP_WNDPROC , cast(LONG_PTR,pOrgProc) )         
         if IsWindow(CTL(wcEdit)) then DestroyWindow( CTL(wcEdit) )         
      end if
      if OrgLinesProc then 
         var pOrgProc = OrgLinesProc : OrgLinesProc = @DefWindowProc
         SetWindowLongPtr( CTL(wcLines) , GWLP_WNDPROC , cast(LONG_PTR,pOrgProc) )
         if IsWindow(CTL(wcLines)) then DestroyWindow( CTL(wcLines) )
      end if
    #endif
    PostQuitMessage(0) ' to quit
    return 0
  case WM_NCDESTROY 'Windows was closed/destroyed
    PostQuitMessage(0) ' to quit
  return 0 
  end select
  
  'if message = g_FindRepMsg then return Edit_FindReplaceAction( *cptr(FINDREPLACE ptr,lParam) )
  
  ' *** if program reach here default predefined action will happen ***
  return DefWindowProc( hWnd, message, wParam, lParam )
    
end function


' *********************************************************************
' *********************** SETUP MAIN WINDOW ***************************
' *********************************************************************
sub WinMain ()
   
   dim tMsg as MSG
   dim tcls as WNDCLASS
   dim as HWND hWnd
    
  '' Setup Splitter class
  with tcls
    .style = 0
    .lpfnWndProc   = @SplitterWndProc
    .cbClsExtra    = 0
    .cbWndExtra    = 8
    .hInstance     = g_AppInstance
    .hIcon         = NULL
    .hCursor       = NULL
    .hbrBackground = cast(HBRUSH,COLOR_3DSHADOW+1)
    .lpszMenuName  = NULL
    .lpszClassName = @"Splitter"
  end with
    
  '' Register the window class     
  if( RegisterClass( @tcls ) = FALSE ) then
    MessageBox( null, "Failed to register wcls!", sAppName, MB_ICONINFORMATION )
    exit sub
  end if  
  
  '' Setup window class
  with tcls
    .style         = 0 'CS_HREDRAW or CS_VREDRAW
    .lpfnWndProc   = @WndProc
    .cbClsExtra    = 0
    .cbWndExtra    = 0
    .hInstance     = g_AppInstance
    .hIcon         = LoadIcon( g_AppInstance, "FB_PROGRAM_ICON" )
    .hCursor       = LoadCursor( NULL, IDC_ARROW )
    .hbrBackground = GetSysColorBrush( COLOR_BTNFACE )
    .lpszMenuName  = NULL
    .lpszClassName = strptr( sAppName )
  end with
  
  '' Register the window class     
  if( RegisterClass( @tcls ) = FALSE ) then
    MessageBox( null, "Failed to register wcls!", sAppName, MB_ICONINFORMATION )
    exit sub
  end if
  
  var hMenu = cast(HMENU,0) 'CreateMainMenu()
  var hAcceleratos = cast(HACCEL,0) 'CreateMainAccelerators()

  const cStyleEx = WS_EX_ACCEPTFILES or WS_EX_LAYERED 'or WS_EX_COMPOSITED
  const cStyle   = WS_TILEDWINDOW or WS_CLIPSIBLINGS 'or WS_MAXIMIZE or WS_CLIPCHILDREN
  
  hWnd = CreateWindowEx(cStyleEx,sAppName,sAppName, cStyle , _ 
  0,0,320,200,null,hMenu,g_AppInstance,0) 'g_tCfg.lGuiX,g_tCfg.lGuiY
  'SetClassLong( hwnd , GCL_HBRBACKGROUND , CLNG(GetSysColorBrush(COLOR_INFOBK)) )
  SetLayeredWindowAttributes( hwnd , GetSysColor(COLOR_INFOBK) , 252 , LWA_COLORKEY )  
  
  '' Process windows messages
  ' *** all messages(events) will be read converted/dispatched here ***
  
  ShowWindow( hWnd , SW_SHOW )
  UpdateWindow( hWnd )
  
  ''PostMessage( hWnd , WM_USER+80 , 0,0 )  
  
  dim as HWND hOldFocus = cast(HWND,-1)
  while( GetMessage( @tMsg, NULL, 0, 0 ) <> FALSE )    
    if TranslateAccelerator( hWnd , hAcceleratos , @tMsg ) then continue while      
    if IsDialogMessage( GetActiveWindow() , @tMsg ) then continue while
    TranslateMessage( @tMsg )
    DispatchMessage( @tMsg )    
    #if 0
      ProcessMessage( tMsg )
      var hFocus = GetFocus()
      if hFocus <> hOldFocus then
         static as long iOnce = 0
         if hOldFocus=cast(HWND,-1) then SetForegroundWindow( hWnd )
         hOldFocus = hFocus
         if g_hContainer andalso g_hSearch then
            if hFocus=NULL orelse (hFocus <> g_hSearch andalso hFocus <> g_hContainer andalso hFocus <> CTL(wcEdit)) then
               ShowWindow( g_hContainer , SW_HIDE )
            end if
         end if
      end if
    #endif
  wend 

  #if 0
    puts("Checking settings")
    if IsWindow( hWnd ) then
      dim as boolean bMaximized = (IsZoomed( hWnd )<>0)
      if bMaximized orelse (IsIconic(hWnd)<>0) then ShowWindow( hWnd , SW_SHOWNORMAL )
      dim as RECT tRcWnd , tRcCli
      GetWindowRect( hWnd , @tRcWnd ) : GetClientRect( hWnd , @tRcCli )
      if bMaximized <> g_tCfg.bGuiMaximized then 
         g_tCfg.bGuiMaximized = bMaximized 
      end if
      if tRcWnd.left <> g_tCfg.lGuiX orelse tRcWnd.top <> g_tCfg.lGuiY then
         g_tCfg.lGuiX = tRcWnd.left : g_tCfg.lGuiY = tRcWnd.top 
      end if
      if tRcCli.right <> g_tCfg.lGuiWid orelse tRcCli.bottom <> g_tCfg.lGuiHei then
         g_tCfg.lGuiWid = tRcCli.right : g_tCfg.lGuiHei = tRcCli.bottom  
      end if
      if IsZoomed(g_GfxHwnd) orelse IsIconic(g_GfxHwnd) then ShowWindow( g_GfxHwnd , SW_SHOWNORMAL )
      GetWindowRect( g_GfxHwnd , @tRcWnd ) : GetClientRect( g_GfxHwnd , @tRcCli )
      if tRcWnd.left <> g_tCfg.lGfxX orelse tRcWnd.top <> g_tCfg.lGfxY then
         g_tCfg.lGfxX = tRcWnd.left : g_tCfg.lGfxY = tRcWnd.top 
      end if
      if tRcCli.right <> g_tCfg.lGfxWid orelse tRcCli.bottom <> g_tCfg.lGfxHei then
         g_tCfg.lGfxWid = tRcCli.right : g_tCfg.lGfxHei = tRcCli.bottom
      end if
    end if   
    SaveSettings()
  #endif

end sub

'if ParseCmdLine()=0 then 
   sAppName = "LegoScript"
   InitCommonControls()
   'if LoadLibrary("Riched20.dll")=0 then
   '  MessageBox(null,"Failed To Load richedit component",null,MB_ICONERROR)
   '  end
   'end if
   'g_FindRepMsg = RegisterWindowMessage(FINDMSGSTRING)
   g_AppInstance = GetModuleHandle(null)  
   
   WinMain() '<- main function
'end if

g_DoQuit = 1
puts("Waiting viewer thread")
if g_ViewerThread then ThreadWait( g_ViewerThread )

