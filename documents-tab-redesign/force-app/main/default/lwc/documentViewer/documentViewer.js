import { api, LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import FORM_FACTOR from '@salesforce/client/formFactor';

import getDocs from '@salesforce/apex/DocumentViewerController.getDocs';
import deleteFile from '@salesforce/apex/DocumentViewerController.deleteFile';
import renameFolder from '@salesforce/apex/DocumentViewerController.renameFolder';
import renameFile from '@salesforce/apex/DocumentViewerController.renameFile';
import getLoanConditions from '@salesforce/apex/DocumentViewerController.getLoanConditions';
import relateFileToCondition from '@salesforce/apex/DocumentViewerController.relateFileToCondition';
import changeFolder from '@salesforce/apex/DocumentViewerController.changeFolder';
import getDefaultFolders from '@salesforce/apex/FileUploaderController.getDefaultFolders';
import moveFiles from '@salesforce/apex/DocumentViewerController.moveFiles';
import applyUploadDetails from '@salesforce/apex/DocumentViewerController.applyUploadDetails';


export default class DocumentViewer extends NavigationMixin(LightningElement) {
	@api recordId;
	@track isLoading = true;
	@track allFolders = [];
	@track folders = [];
	@track docs = [];
	@track foldersToFilesMap = new Map();
	@track filter;
	@track deleteModalOpen = false;
	@track fileToDelete;
	@track renameFolderModalOpen = false;
	@track isNewFolderNameInvalid = true;
	@track fileToRename;
	@track isNewFileNameInvalid = true;
	@track renameFileModalOpen = false;
	@track folderToChange;
	@track changeFolderModalOpen = false;
	@track isNewFolderForFileInvalid = true;
	@track relateConditionModalOpen = false;
	@track relateConditionDisabled = true;
	@track fileToRelate;
	@track conditions = [];
	@track defaultFolders = [];
	@track addDocumentModalOpen = false;
	@track uploadFolder;
	@track uploadLabel = '';
	TRANSACTION_ID_PREFIX = 'a01';
	DEFAULT_UPLOAD_FOLDER = 'Conditions';
	isCompactView = FORM_FACTOR !== 'Large';
	ERROR_TOAST_VARIANT = 'error';
	SUCCESS_TOAST_VARIANT = 'success';

	@track activeFolders = [];
	selectedFolderName;
	NO_FOLDER = 'No Folder';

	// Drag state. Only the id travels; the file itself is looked up on drop.
	dragFileId;
	dragFromFolder;
	dragOverFolder;
	dropTargetId;
	dropBefore = true;

	connectedCallback() {
		this.showSpinner();
		getDocs({recordId: this.recordId})
			.then((result) => {
				this.onGetDocsSuccess(result);
				this.closeSpinner();
			})
			.catch((e) => {
				console.log(e);
				console.error('e.name => ', e?.name);
				console.error('e.message => ', e?.message);
				console.error('e.stack => ', e?.stack);
				this.onGetDocsFail();
				this.closeSpinner();
			});
	}

	showSpinner() {
		this.isLoading = true;
	}

	closeSpinner() {
		this.isLoading = false;
	}

	onGetDocsSuccess(docs) {
		this.docs = this.getParsedDocs(docs);

		getDefaultFolders()
			.then((result ) => {
				this.onGetDefaultFoldersSuccess(result)
			})
			.catch((e) => {
				console.log(e);
				console.error('e.name => ', e?.name);
				console.error('e.message => ', e?.message);
				console.error('e.stack => ', e?.stack);
				this.closeSpinner();
			});
	}

	onGetDocsFail() {
		this.showToast('An error occurred while retrieving documents', this.ERROR_TOAST_VARIANT);
	}

	showToast(title, variant) {
		const toastEvent = new ShowToastEvent({
			title, 
			variant: variant
		});
		this.dispatchEvent(toastEvent);
	}

	/** Safe message for Apex / wire errors (body may be missing). */
	apexErrorMessage(error, fallback) {
		if (!error) {
			return fallback;
		}
		const body = error.body;
		if (body?.message) {
			return body.message;
		}
		const firstPageError = body?.pageErrors?.[0];
		if (firstPageError?.message) {
			return firstPageError.message;
		}
		if (typeof error.message === 'string' && error.message.length > 0) {
			return error.message;
		}
		return fallback;
	}

	getParsedDocs(docs) {
		const parsedDocs = [];

		for (const doc of docs) {
			doc.url = `/sfc/servlet.shepherd/document/download/${doc.id}`;
			doc.fileNameWithType = doc.fileName + '.' + doc.fileType;
			doc.thumbnailUrl = doc.versionId
				? `/sfc/servlet.shepherd/version/renditionDownload?rendition=THUMB240BY180&versionId=${doc.versionId}`
				: null;
			doc.formattedCreatedDate = this.formatCreatedDate(doc.createdDate);
			doc.shortDate = doc.createdDate
				? new Intl.DateTimeFormat('en-US', { month: 'short', day: 'numeric', year: 'numeric' }).format(new Date(doc.createdDate))
				: '';
			doc.hasCondition = !!doc.conditionName && doc.conditionName !== 'None';
			doc.displayIcon = doc.fileTypeIcon || 'doctype:unknown';
			parsedDocs.push(doc);
		}

		return parsedDocs;
	}

	formatCreatedDate(dateValue) {
		if (!dateValue) {
			return '';
		}

		return new Intl.DateTimeFormat('en-US', {
			day: 'numeric',
			month: 'short',
			year: 'numeric',
			hour: '2-digit',
			minute: '2-digit',
			hour12: false
		}).format(new Date(dateValue));
	}

	findFileById(fileId) {
		for (const folder of this.folders) {
			const file = folder.data.find((doc) => doc.id === fileId);
			if (file) {
				return file;
			}
		}

		return null;
	}

	handleMobilePreview(event) {
		const fileId = event.currentTarget.dataset.fileId;
		const file = this.findFileById(fileId);

		if (file) {
			this.handlePreview(file);
		}
	}

	handleMobileFileAction(event) {
		const fileId = event.currentTarget.dataset.fileId;
		const actionName = event.detail.value;
		const file = this.findFileById(fileId);

		if (!file) {
			return;
		}

		switch (actionName) {
			case 'download':
				this.handleDownload(file);
				break;
			case 'renameFile':
				this.openRenameFileModal(file);
				break;
			case 'changeFolder':
				this.openChangeFolderModal(file);
				break;
			case 'delete':
				this.openDeleteModal(file);
				break;
			case 'relateCondition':
				this.openConditionPickModal(file);
				break;
			default:
				break;
		}
	}

	setFolders(parsedDocs) {
		const folders = [];
		const foldersToFilesMap = new Map();

		// Replace this with your list of default folders
		const defaultFolders = this.defaultFolders;

		// Iterate through default folders and add them to the folders array
		for (const folder of defaultFolders) {
			folders.push({
				name: folder.value,
				data: [], // Empty array since no documents are found
				newName: folder.value
			});
			this.activeFolders.push(folder.value);
			foldersToFilesMap.set(folder.value, []);
		}

		for (const doc of parsedDocs) {
			const folderName = doc.folderName || 'No Folder';
			doc.folderName = folderName;

			if (!foldersToFilesMap.has(folderName)) {
				folders.push({
					name: folderName,
					data: [doc],
					newName: folderName
				});
				this.activeFolders.push(folderName);
				foldersToFilesMap.set(folderName, [doc]);
				continue;
			}

			const foundFolder = folders.find(element => element.name === folderName);
			foundFolder.data.push(doc);
			const docsByFolder = [...foldersToFilesMap.get(folderName), doc];
			foldersToFilesMap.set(folderName, docsByFolder);
		}

		// Files someone has dragged into place keep that order; the rest follow in the order Apex
		// returned them. Array.sort is stable, so ties keep that order too.
		const position = (doc) => (doc.sortOrder === null || doc.sortOrder === undefined ? Infinity : doc.sortOrder);
		for (const folder of folders) {
			folder.data.sort((a, b) => position(a) - position(b));
		}

		this.folders = folders;

		this.folders.sort((a, b) => {
			if (a.name === 'No Folder') return -1;
			if (b.name === 'No Folder') return 1;
			return a.name.localeCompare(b.name);
		});

		this.foldersToFilesMap = foldersToFilesMap;
			}

	// Hidden on a Transaction, where documents come in through the processing tools with their
	// own rules about placement. Written as "not a Transaction" rather than "is a Lead" so an
	// unexpected or late-arriving recordId leaves the button visible rather than silently gone.
	get canAddDocument() {
		return !(typeof this.recordId === 'string' && this.recordId.startsWith(this.TRANSACTION_ID_PREFIX));
	}

	get folderOptions() {
		return this.defaultFolders;
	}

	openAddDocumentModal() {
		const hasDefault = this.defaultFolders.some(
			(folder) => folder.value === this.DEFAULT_UPLOAD_FOLDER
		);
		this.uploadFolder = hasDefault
			? this.DEFAULT_UPLOAD_FOLDER
			: this.defaultFolders[0] && this.defaultFolders[0].value;
		this.uploadLabel = '';
		this.addDocumentModalOpen = true;
	}

	closeAddDocumentModal() {
		this.addDocumentModalOpen = false;
		this.uploadLabel = '';
	}

	handleUploadFolderChange(event) {
		this.uploadFolder = event.detail.value;
	}

	handleUploadLabelChange(event) {
		this.uploadLabel = event.detail.value;
	}

	handleUploadFinished(event) {
		const uploaded = (event.detail && event.detail.files) || [];
		const contentVersionIds = uploaded
			.map((file) => file.contentVersionId)
			.filter(Boolean);
		if (contentVersionIds.length === 0) {
			// The file is already attached to the record; only the filing failed to resolve.
			this.showToast(
				'Document added, but it could not be filed automatically. Use Change Folder on the row.',
				this.ERROR_TOAST_VARIANT
			);
			this.closeAddDocumentModal();
			this.connectedCallback();
			return;
		}

		this.showSpinner();
		applyUploadDetails({
			contentVersionIds,
			folderName: this.uploadFolder,
			documentLabel: this.uploadLabel
		})
			.then(() => {
				const count = contentVersionIds.length;
				this.showToast(
					`${count === 1 ? 'Document' : `${count} documents`} added to ${this.uploadFolder}.`,
					this.SUCCESS_TOAST_VARIANT
				);
				this.closeAddDocumentModal();
				this.connectedCallback();
			})
			.catch((error) => {
				this.closeSpinner();
				// The upload itself succeeded, so say so rather than implying nothing happened.
				this.showToast(
					this.apexErrorMessage(
						error,
						'Document added, but the folder and label could not be applied.'
					),
					this.ERROR_TOAST_VARIANT
				);
				this.closeAddDocumentModal();
				this.connectedCallback();
			});
	}

	onGetDefaultFoldersSuccess(folders) {
		const defaultFolders = [];
	
		for (const folder of folders) {
			defaultFolders.push({
				label: folder.MasterLabel,
				value: folder.MasterLabel
			});
		}

		this.defaultFolders = defaultFolders;

		this.setFolders(this.docs);
		this.allFolders = [...this.folders];
		const stillThere = this.allFolders.some((folder) => folder.name === this.selectedFolderName);
		if (!stillThere) {
			const firstWithFiles = this.allFolders.find((folder) => folder.data.length > 0);
			this.selectedFolderName = (firstWithFiles || this.allFolders[0] || {}).name;
		}
		getLoanConditions({recordId: this.recordId})
			.then((conditions) => {
				const conditionOptions = [{label:'None', value: 'None'}];
				for (const condition of conditions) {
					const option = {label: condition.Name, value: condition.Id}
					conditionOptions.push(option);
				}
				this.conditionOptions = conditionOptions;
			})
			.catch((error) => {
				console.log('error on getLoanConditions');
				console.log(error?.message);
				console.log(error?.stack);
			})
	}

	handleFilterChange(event) {
		this.filter = event.target.value;
	}

	handleFilterFiles() {
		this.showSpinner();
		
		if (this.filter) {
			this.filterFiles();
		} else {
			this.resetFilter();
		}
		
		this.closeSpinner();
	}

	resetFilter() {
		this.folders = this.allFolders;
		this.activeFolders = [];
	}

	filterFiles() {
		this.folders = [];
		this.activeFolders = [];
		const folders = [...this.allFolders];
		const filter = this.filter.toLowerCase();

		for (const folder of folders) {
			const filteredFiles = [];
		
			for (const file of folder.data) {
				if (file.fileNameWithType.toLowerCase().includes(filter)) {
					filteredFiles.push(file);
				}
			}

			if (filteredFiles.length > 0) {
				const newFolder = {...folder, data: filteredFiles};
				this.folders.push(newFolder);
				this.activeFolders.push(folder.name);
			}
		}
	}

	downloadAllFiles() {
		const downloadUrl = this.getDownloadUrl(this.docs);

		this[NavigationMixin.Navigate]({ 
			type:'standard__webPage',
			attributes: { 
				url: downloadUrl
			}
		});
	}

	openRenameFolderModal(event) {
		const folderIndex = event.target.dataset.index;
		this.folderToRename = this.folders[folderIndex];
		this.renameFolderModalOpen = true;
	}

	get renameFolderLabel() {
		return 'Please enter new name for "' + this.folderToRename.name +'" folder';
	}

	closeRenameFolderModal() {
		this.folderToRename = null;
		this.renameFolderModalOpen = false;
		this.isNewFolderNameInvalid = false;
	}

	validateNewFolderName(event) {
		if (event.target.value === undefined || event.target.value == null ) {
			this.isNewFolderNameInvalid = false;
			return;
		}

		const newFolderName = event.target.value.trim();
		this.isNewFolderNameInvalid = !event.target.reportValidity() 
			|| newFolderName === this.folderToRename.name;
		this.folderToRename.newName = event.target.value;
	}

	handleFolderRename() {
		this.showSpinner();
		const oldFolderName = this.folderToRename.name;
		const newFolderName = this.folderToRename.newName;

		const params = {
			recordId : this.recordId,
			oldFolderName : oldFolderName,
			newFolderName : newFolderName.trim()
		};

		this.closeRenameFolderModal();
		renameFolder(params)
			.then(() => {
				const successMessage = 'Folder "' + oldFolderName
					+ '" was successfully renamed to "' + newFolderName.trim() + '".'
				this.showToast(successMessage, this.SUCCESS_TOAST_VARIANT);
				this.connectedCallback();
			})
			.catch(e => {
				this.closeSpinner();
				const errorMessage = this.apexErrorMessage(
					e,
					'An error occurred during folder rename. Please, try again.'
				);
				this.showToast(errorMessage, this.ERROR_TOAST_VARIANT);
			});
	}

	downloadFolder(event) {
		const folderIndex = event.target.dataset.index;
		const folderToDownload = this.folders[folderIndex];
		const downloadUrl = this.getDownloadUrl(folderToDownload.data);

		this[NavigationMixin.Navigate]({ 
			type:'standard__webPage',
			attributes: { 
				url: downloadUrl
			}
		});
	}

	getDownloadUrl(files) {
		let downloadUrl = `/sfc/servlet.shepherd/document/download`;
	
		for (const file of files) {
			downloadUrl += '/' + file.id;
		}

		downloadUrl += '?';

		return downloadUrl;
	}

	handlePreview(row) {
		this[NavigationMixin.Navigate]({ 
			type:'standard__namedPage',
			attributes:{ 
				pageName:'filePreview'
			},
			state:{ 
				selectedRecordId: row.id
			}
		})
	}

	handleDownload(row) {
		this[NavigationMixin.Navigate]({
			type: "standard__webPage",
			attributes: {
				url: row.url,
			},
		});
	}

	openRenameFileModal(row) {
		this.fileToRename = row;
		this.renameFileModalOpen = true;
	}

	closeRenameFileModal() {
		this.fileToRename = null;
		this.isNewFileNameInvalid = true;
		this.renameFileModalOpen = false;
	}

	validateNewFileName(event) {
		const value = event.target.value.trim();
		this.isNewFileNameInvalid = !event.target.reportValidity() 
			|| value === this.fileToRename.fileName || !value;

		if (this.isNewFileNameInvalid) {
			return;
		}
	
		const fileToRename = {...this.fileToRename};
		fileToRename.newName = value;
		this.fileToRename = fileToRename;
	}

	handleFileRename() {
		const fileToRename = {...this.fileToRename};
		this.fileToRename = null;
		this.closeRenameFileModal();
		this.showSpinner();
		const params = {
			fileId: fileToRename.id,
			newFileName: fileToRename.newName
		};

		renameFile(params)
			.then(() => {
				const successMessage = 'File "' + fileToRename.fileName + '.' + fileToRename.fileType
					+ '" was renamed to "' + fileToRename.newName + '.' + fileToRename.fileType + '"';
				this.showToast(successMessage, this.SUCCESS_TOAST_VARIANT);
				this.connectedCallback()
			})
			.catch(error => {
				const errorMessage = this.apexErrorMessage(
					error,
					'An error occurred during file rename. Please, try again.'
				);
				this.showToast(errorMessage, this.ERROR_TOAST_VARIANT);
			})
	}

	openChangeFolderModal(row) {
		this.fileToChangeFolder = row;
		this.changeFolderModalOpen = true;
	}

	closeChangeFolderModal() {
		this.fileToChangeFolder = null;
		this.newFolderForFile = null;
		this.changeFolderModalOpen = false;
		this.isNewFolderForFileInvalid = true;
	}

	get changeFolderOptions() {
		let options = [];
		const uniqueFolderNames = [];
	
		for (const folder of this.folders) {
			if (folder.name !== this.fileToChangeFolder.folderName) {
				options.push({
					label: folder.name,
					value: folder.name
				});
				uniqueFolderNames.push(folder.name);
			}
		}

		const uniqueDefaultFolders = this.defaultFolders.filter(
			(folder) => !uniqueFolderNames.includes(folder.value)
		);

		options = [...options, ...uniqueDefaultFolders];

		return options;
	}

	handleNewFolderSelect(event) {
		this.newFolderForFile = event.target.value;
		this.isNewFolderForFileInvalid = !event.target.value;
	}

	handleFolderChange(event) {
		const params = {
			recordId: this.recordId,
			fileId: this.fileToChangeFolder.id,
			newFolderName: this.newFolderForFile
		};
		this.closeChangeFolderModal();
		this.showSpinner();
	
		changeFolder(params)
			.then(() => {
				this.showToast('Folder was successfully changed', this.SUCCESS_TOAST_VARIANT);
				this.connectedCallback();
			})
			.catch(error => {
				this.closeSpinner();
				console.log('ERROR DURING CHANGE FOLDER');
				console.log(error);
				const errorMessage = this.apexErrorMessage(
					error,
					'An error occurred while changing folder. Please, try again.'
				);
				this.showToast(errorMessage, this.ERROR_TOAST_VARIANT);
			})
	}

	openDeleteModal(row) {
		this.fileToDelete = row;
		this.deleteModalOpen = true;
	}

	closeDeleteModal() {
		this.deleteModalOpen = false;
		this.fileToDelete = null;
	}

	handleFileDelete() {
		const fileToDelete = {...this.fileToDelete};
		this.showSpinner();
		this.closeDeleteModal();

		deleteFile({fileId: fileToDelete.id})
			.then(() => {
				const successMessage = 'File "'
					+ fileToDelete.fileName + '.' + fileToDelete.fileType
					+ '" was successfully deleted.'
				this.showToast(successMessage, this.SUCCESS_TOAST_VARIANT);
				this.connectedCallback();
			})
			.catch(e => {
				const errorMessage = this.apexErrorMessage(
					e,
					'An error occurred during document deletion. Please, try again'
				);
				this.showToast(errorMessage, this.ERROR_TOAST_VARIANT);
				this.closeSpinner();
			})
	}

	openConditionPickModal(row) {
		try {
			this.fileToRelate = row;
			this.relateConditionModalOpen = true;
		} catch(e) {
			console.log('error on openConditionPickModal');
			console.log(e?.message);
			console.log(e?.stack);
		}
	}

	closeConditionPickModal() {
		this.fileToRelate = null;
		this.relateConditionModalOpen = false;
		this.relateConditionDisabled = true;
	}

	handleNewConditionPick(event) {
		this.conditionToRelate = event.target.value !== 'None' ? event.target.value : null;
		this.relateConditionDisabled = event.target.value === this.fileToRelate.conditionId;
	}

	handleConditionRelate() {
		try {
			this.showSpinner();
			relateFileToCondition({fileId: this.fileToRelate.id, conditionId: this.conditionToRelate})
				.then(() => {
					const successMessage = 'File "'
						+ this.fileToRelate.fileName + '.' + this.fileToRelate.fileType
						+ '" was successfully related to condition.';
					this.closeConditionPickModal();
					this.showToast(successMessage, this.SUCCESS_TOAST_VARIANT);
					this.connectedCallback();
				})
				.catch((e) => {
					const errorMessage = this.apexErrorMessage(
						e,
						'An error occurred during Loan Condition change on file. Please, try again'
					);
					this.closeConditionPickModal();
					this.showToast(errorMessage, this.ERROR_TOAST_VARIANT);
					this.closeSpinner();
				})
		} catch(e) {
			console.log('error on handleConditionRelate');
			console.log(e?.message);
			console.log(e?.stack);
		}
	}

	// ---------- Desktop: folder rail and file grid ----------

	matchesFilter(file) {
		return !this.filter || file.fileNameWithType.toLowerCase().includes(this.filter.toLowerCase());
	}

	get railFolders() {
		return this.allFolders.map((folder) => {
			const isSelected = folder.name === this.selectedFolderName;
			const count = folder.data.filter((file) => this.matchesFilter(file)).length;
			let cssClass = 'dv-rail__item';
			if (isSelected) cssClass += ' is-selected';
			if (!count) cssClass += ' is-empty';
			if (folder.name === this.dragOverFolder) cssClass += ' is-drop';
			return {
				name: folder.name,
				count,
				cssClass,
				icon: isSelected ? 'utility:open_folder' : 'utility:folder',
				ariaCurrent: isSelected ? 'true' : 'false'
			};
		});
	}

	get selectedFolder() {
		return this.allFolders.find((folder) => folder.name === this.selectedFolderName);
	}

	get visibleFiles() {
		const folder = this.selectedFolder;
		if (!folder) {
			return [];
		}
		return folder.data
			.filter((file) => this.matchesFilter(file))
			.map((file) => {
				let cssClass = 'dv-card';
				if (file.id === this.dragFileId) cssClass += ' is-dragging';
				if (file.id === this.dropTargetId) cssClass += this.dropBefore ? ' drop-before' : ' drop-after';
				return { ...file, cssClass };
			});
	}

	get hasVisibleFiles() {
		return this.visibleFiles.length > 0;
	}

	get emptyStateText() {
		return this.filter ? 'No documents in this folder match your search.' : 'This folder is empty.';
	}

	handleFolderSelect(event) {
		this.selectedFolderName = event.currentTarget.dataset.name;
	}

	handleFolderMenu(event) {
		const folder = this.selectedFolder;
		if (!folder) {
			return;
		}
		if (event.detail.value === 'rename') {
			this.folderToRename = folder;
			this.renameFolderModalOpen = true;
		} else if (event.detail.value === 'download' && folder.data.length) {
			this[NavigationMixin.Navigate]({
				type: 'standard__webPage',
				attributes: { url: this.getDownloadUrl(folder.data) }
			});
		}
	}

	// No rendition exists for some types (zip, msg...). Hiding the broken image uncovers the
	// file-type icon rendered underneath it.
	handleThumbError(event) {
		event.target.style.display = 'none';
	}

	handleDragStart(event) {
		this.dragFileId = event.currentTarget.dataset.id;
		this.dragFromFolder = this.selectedFolderName;
		event.dataTransfer.effectAllowed = 'move';
		// Firefox will not start a drag without data.
		event.dataTransfer.setData('text/plain', this.dragFileId);
	}

	handleDragEnd() {
		this.dragFileId = null;
		this.dragFromFolder = null;
		this.dragOverFolder = null;
		this.dropTargetId = null;
	}

	handleCardDragOver(event) {
		if (!this.dragFileId) {
			return;
		}
		event.preventDefault();
		event.stopPropagation();
		const targetId = event.currentTarget.dataset.id;
		const rect = event.currentTarget.getBoundingClientRect();
		const before = event.clientX < rect.left + rect.width / 2;
		if (targetId === this.dragFileId) {
			this.dropTargetId = null;
		} else if (targetId !== this.dropTargetId || before !== this.dropBefore) {
			this.dropTargetId = targetId;
			this.dropBefore = before;
		}
	}

	handleGridDragOver(event) {
		if (this.dragFileId) {
			event.preventDefault();
		}
	}

	handleCardDrop(event) {
		event.preventDefault();
		event.stopPropagation();
		this.dropWithinFolder(this.dropTargetId, this.dropBefore);
	}

	// Dropped on the gap between cards: send it to the end.
	handleGridDrop(event) {
		event.preventDefault();
		this.dropWithinFolder(null, false);
	}

	dropWithinFolder(targetId, before) {
		const fileId = this.dragFileId;
		const folder = this.selectedFolder;
		this.handleDragEnd();
		if (!fileId || !folder || fileId === targetId) {
			return;
		}
		const ids = folder.data.map((file) => file.id).filter((id) => id !== fileId);
		let index = targetId ? ids.indexOf(targetId) : ids.length;
		if (index < 0) index = ids.length;
		if (targetId && !before) index += 1;
		ids.splice(index, 0, fileId);

		const unchanged = ids.every((id, i) => id === folder.data[i].id);
		if (!unchanged) {
			this.saveMove(fileId, folder.name, ids);
		}
	}

	handleFolderDragOver(event) {
		const name = event.currentTarget.dataset.name;
		// "No Folder" is only where unfiled documents collect; it is not something to file into.
		if (!this.dragFileId || name === this.dragFromFolder || name === this.NO_FOLDER) {
			return;
		}
		event.preventDefault();
		event.dataTransfer.dropEffect = 'move';
		this.dragOverFolder = name;
	}

	handleFolderDragLeave(event) {
		if (this.dragOverFolder === event.currentTarget.dataset.name) {
			this.dragOverFolder = null;
		}
	}

	handleFolderDrop(event) {
		event.preventDefault();
		const fileId = this.dragFileId;
		const target = this.allFolders.find((folder) => folder.name === event.currentTarget.dataset.name);
		this.handleDragEnd();
		if (!fileId || !target) {
			return;
		}
		this.saveMove(fileId, target.name, [...target.data.map((file) => file.id), fileId]);
	}

	// Moves the card on screen straight away, then saves. A failed save reloads from the server
	// so the screen never shows an order that was not kept.
	saveMove(fileId, folderName, orderedIds) {
		const byId = new Map(this.docs.map((doc) => [doc.id, doc]));
		const fromFolder = byId.get(fileId).folderName;

		const folders = this.allFolders.map((folder) => {
			if (folder.name === folderName) {
				const data = orderedIds.map((id, i) => Object.assign(byId.get(id), { folderName, sortOrder: i }));
				return { ...folder, data };
			}
			return { ...folder, data: folder.data.filter((file) => file.id !== fileId) };
		});
		this.folders = folders;
		this.allFolders = [...folders];

		moveFiles({ recordId: this.recordId, folderName, orderedFileIds: orderedIds })
			.then(() => {
				if (fromFolder !== folderName) {
					this.showToast(`Moved to ${folderName}`, this.SUCCESS_TOAST_VARIANT);
				}
			})
			.catch((error) => {
				this.showToast(
					this.apexErrorMessage(error, 'That move could not be saved. Try again.'),
					this.ERROR_TOAST_VARIANT
				);
				this.connectedCallback();
			});
	}
}
