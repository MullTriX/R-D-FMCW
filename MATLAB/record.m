clear dca
% Create connection to the TI Radar board and DCA1000EVM Capture card
dca = dca1000("IWR6843ISK");
% Specify the duration to record ADC data
dca.RecordDuration = 10;
% Specify the location at which you want to store the recorded data along
% with the recording parameters
dca.RecordLocation = "Dataset\10s_coś";
% Start recording.
% The function startRecording opens a window. Ensure that you do not
% close this window. It will automatically close when the recording
% finishes.
startRecording(dca);
% The startRecording function captures data in background.
% While this is happening, you are free to utilize MATLAB for any other
% tasks you might need to perform. The following code is designed to
% prevent MATLAB from proceeding until the recording has finished.
% The isRecording() function will return true if the recording is still
% in progress. Once the recording has concluded or if it has not started,
% the function will return false.
while isRecording(dca)
end
% Remember the record location for post-processing.
% In this example, we will save the recording location in a variable.
recordLocation = dca.RecordLocation;
% Clear the dca1000 object and remove the hardware connections if required
clear dca