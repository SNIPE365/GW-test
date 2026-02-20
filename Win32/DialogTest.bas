#cmdline "res\LS.rc"

#define _WIN32_WINNT &h0600
#include once "windows.bi"
#include once "win/commctrl.bi"

Sub ShowCustomDialog()
  Dim tdc as TASKDIALOGCONFIG
  Dim as integer nButton
  
  '' Custom Button IDs
  #define ID_SAVE 101
  #define ID_DONT_SAVE 102
  #define ID_CANCEL 103
  
  '' Define the custom buttons
  Dim buttons(0 to 2) as TASKDIALOG_BUTTON
  buttons(0).nButtonID = ID_SAVE
  buttons(0).pszButtonText = @wstr("Save")    
  buttons(1).nButtonID = ID_DONT_SAVE
  buttons(1).pszButtonText = @wstr("Don't Save")    
  buttons(2).nButtonID = ID_CANCEL
  buttons(2).pszButtonText = @wstr("Cancel")

  '' Setup the Config Structure
  with tdc
    .cbSize = len(tdc)
    .hwndParent = NULL
    .dwFlags = TDF_ALLOW_DIALOG_CANCELLATION
    .pszWindowTitle = @wstr("Unsaved Changes")
    .pszMainInstruction = @wstr("Do you want to save your changes?")
    .pszContent = @wstr("If you don't save, your work will be lost.")
    .hMainIcon = cast(any ptr,TD_WARNING_ICON)
  end with
  
  '' Link the buttons
  tdc.cButtons = 3 : tdc.pButtons = @buttons(0)
    
  TaskDialogIndirect(@tdc, @nButton, NULL, NULL)      
  Select Case nButton
  Case ID_SAVE
    Print "User chose SAVE"
  Case ID_DONT_SAVE
    Print "User chose DON'T SAVE"
  Case ID_CANCEL
    Print "User chose CANCEL"
  End Select

End Sub

InitCommonControls()

ShowCustomDialog()

Sleep