import { LightningElement, api, track } from 'lwc';
import saveFolder from "@salesforce/apex/FileUploaderController.saveFolder";
import getDefaultFolders from "@salesforce/apex/FileUploaderController.getDefaultFolders";
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

//specify namespace @salesforce/apex/namespace.class...

export default class FileUploader extends LightningElement {
	@api recordId;
	ERROR_TOAST_VARIANT = 'error';
	SUCCESS_TOAST_VARIANT = 'success';
	acceptedFormats = ['.pdf','.jpeg','.jpg','.png','.doc','.docx','.xls','.xlsx','.txt','.csv','.heic'];
	newFolderName = 'New Folder';
	
	@track selectedFolder;
	@track isFolderInvalid = true;
	@track isLoading = true;
	@track folderOptions = [];
	@track newFolderModalOpen = false;
	@track newFolder = {
		name : ''
	};
	@track isNewFolderNameInvalid = true;

	connectedCallback() {
		this.showSpinner();
		getDefaultFolders()
		.then(result => {
			this.setDefaultFolders(result);
			this.closeSpinner();
		})
		.catch(error => {
			this.closeSpinner();
			console.log('ERROR ON GET DEFAULT FOLDERS');
			console.log(error);
			console.error('e.name => ' + error.name );
			console.error('e.message => ' + error.message );
			console.error('e.stack => ' + error.stack );
			const errorMessage = 'An error occurred while retrieving default folders.'
			this.showToast(errorMessage, ERROR_TOAST_VARIANT);
		})
	}

	setDefaultFolders(folders) {
		const folderOptions = [];
	
		for (const folder of folders) {
			folderOptions.push({
				label: folder.MasterLabel,
				value: folder.MasterLabel
			});
		}

		folderOptions.push({
			label: this.newFolderName,
			value: this.newFolderName,
		})

		this.folderOptions = folderOptions;
	}

	showToast(title, variant) {
		const toastEvent = new ShowToastEvent({
			title, 
			variant: variant
		});
		this.dispatchEvent(toastEvent);
	}

	showSpinner() {
		this.isLoading = true;
	}

	closeSpinner() {
		this.isLoading = false;
	}

	handleFolderSelect(event) {
		this.selectedFolder = event.target.value;
	
		if (event.target.value == this.newFolderName) {
			this.openNewFolderModal();
			return;
		}

		this.isFolderInvalid = !event.target.reportValidity();
	}

	openNewFolderModal() {
		this.showSpinner();
		this.isFolderInvalid = true;
		this.newFolderModalOpen = true;
		this.closeSpinner();
	}

	closeNewFolderModal() {
		this.showSpinner();
		this.selectedFolder = null;
		this.isNewFolderNameInvalid = true;
		this.newFolderModalOpen = false;
		this.closeSpinner();
	}

	validateNewFolderName(event) {
		const value = event.target.value.trim();
		this.isNewFolderNameInvalid = !event.target.reportValidity() || !value;

		if (this.isNewFolderNameInvalid) {
			return;
		}
	
		this.newFolder = {...this.newFolder, name:value};
	}

	handleNewFolderCreate() {
		this.showSpinner();
		this.setNewFolderOption();
		this.selectedFolder = this.newFolder.name;
		this.newFolderModalOpen = false;
		this.isFolderInvalid = false;
		this.closeSpinner();
	}

	setNewFolderOption() {
		let options = [...this.folderOptions];
		const newFolder = options.pop();
		const createdFolder = {
			label: this.newFolder.name,
			value: this.newFolder.name
		}
		options.push(createdFolder, newFolder);
		this.folderOptions = options;
	}

	handleUploadFinished(event) {
		const uploadedFiles = event.detail.files;
		const params = this.getFolderSaveParams(uploadedFiles);

		saveFolder(params)
		.catch(error => {
			console.log(error);
			const errorMessage = 'An error occurred while saving your folder. File was saved into "No Category" folder';
			this.showToast(errorMessage, this.ERROR_TOAST_VARIANT);
		});
	}

	getFolderSaveParams(uploadedFiles) {
		const contentVersions = [];
	
		for (const uploadedFile of uploadedFiles) {
			contentVersions.push(uploadedFile.contentVersionId);
		}

		const params = {
			contentVersionIds: contentVersions,
			selectedFolder: this.selectedFolder
		};

		return params;
	}
}