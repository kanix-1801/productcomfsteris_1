import { LightningElement, track } from 'lwc';

export default class Cameracapture2 extends LightningElement {
    @track statusMessage = '';

    stream;
    cameras = [];
    selectedCamera;
    capturedImage;

    async connectedCallback() {
        await this.getCameraList();
    }

    async getCameraList() {
         var videoUserMedia = await navigator.mediaDevices.getUserMedia({video: true, audio: false});

        // Get list of cameras
        const devices = await navigator.mediaDevices.enumerateDevices();

        console.log("device: " + devices);
        this.statusMessage = ("Devices found: " + devices.length + "\n");
        devices.forEach((device, index) => {
            console.log(`Device ${index}:`);
            this.statusMessage += `Device ${index}:\n`;
            console.log(`  Kind: ${device.kind}`);
            this.statusMessage += `  Kind: ${device.kind}\n`;
            console.log(`  Label: ${device.label}`);
            this.statusMessage += `  Label: ${device.label}\n`;
            console.log(`  Device ID: ${device.deviceId}`);
            this.statusMessage += `  Device ID: ${device.deviceId}\n`;
            console.log(`  Group ID: ${device.groupId}`);
            this.statusMessage += `  Group ID: ${device.groupId}\n`;
            console.log('---');
            this.statusMessage += '---\n';
        });
        

        try {
            // Request permission first to get device labels
            //const tempStream = await navigator.mediaDevices.getUserMedia({ video: true });
            //tempStream.getTracks().forEach(track => track.stop());

            // Now enumerate devices with labels
            //const devices = await navigator.mediaDevices.enumerateDevices();
            //this.cameras = devices.filter(d => d.kind === 'videoinput');
            
            // Auto-select external camera (usually index 1+)
            //this.selectedCamera = this.cameras.length > 1 ? this.cameras[2].deviceId : this.cameras[0].deviceId;
            this.selectedCamera = devices[1].deviceId;
            
            console.log('selectedCamera:', this.selectedCamera);
        } catch (error) {
            console.error('Error accessing cameras:', error);
        }
    }

    async startCamera() {
        try {
            this.stream = await navigator.mediaDevices.getUserMedia({
                video: { deviceId: { exact: this.selectedCamera } }
            });

            const video = this.refs.videoElement;
            video.srcObject = this.stream;
            await video.play();
        } catch (error) {
            console.error('Failed to start camera:', error);
        }
    }

    captureImage() {
        const video = this.refs.videoElement;
        const canvas = this.refs.canvasElement;
        const context = canvas.getContext('2d');

        canvas.width = video.videoWidth;
        canvas.height = video.videoHeight;
        context.drawImage(video, 0, 0);

        this.capturedImage = canvas.toDataURL('image/png');
        this.stopCamera();
        
        // Display captured image
        const img = this.refs.imageElement;
        img.src = this.capturedImage;
    }

    stopCamera() {
        if (this.stream) {
            this.stream.getTracks().forEach(track => track.stop());
        }
    }

    get hasCapturedImage() {
        return this.capturedImage != null;
    }
}