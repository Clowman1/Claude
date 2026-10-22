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
import finishMerge from '@salesforce/apex/DocumentViewerController.finishMerge';

// What pdf-lib can put into a PDF: PDFs page by page, and photos as a page each.
const MERGEABLE_TYPES = new Set(['pdf', 'jpg', 'jpeg', 'png']);
// Must match SPLIT_PART_TITLE in DocumentViewerController: the borrower portal's split parts.
const SPLIT_PART_TITLE = /\(part \d+ of \d+\)$/;
const BRIDGE_READY_TIMEOUT_MS = 20000;

const FILE_ICONS = {
	pdf: 'doctype:pdf',
	doc: 'doctype:word', docx: 'doctype:word',
	xls: 'doctype:excel', xlsx: 'doctype:excel', csv: 'doctype:csv',
	png: 'doctype:image', jpg: 'doctype:image', jpeg: 'doctype:image', gif: 'doctype:image', heic: 'doctype:image',
	txt: 'doctype:txt', zip: 'doctype:zip'
};
const fileIcon = (ext) => FILE_ICONS[ext] || 'doctype:attachment';


export default class DocumentViewer extends NavigationMixin(LightningElement) {
	_contextRecordKey;
	@api recordId;

	// Set by the Partner Workspace portal, which embeds this viewer outside a record page (Nimbus, 2026-09-30).
	@api
	get contextRecordKey() {
		return this._contextRecordKey;
	}

	set contextRecordKey(value) {
		this._contextRecordKey = value;
	}

	get resolvedRecordId() {
		return this.contextRecordKey || this.recordId;
	}
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
	stagedFiles = [];
	addDocDragging = false;
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

	// Ticked documents, kept across folders so a download can mix them. Replaced, never mutated,
	// so the template re-renders. A Set keeps insertion order, which is the order they were
	// clicked: that is the page order of a merge.
	selectedIds = new Set();

	mergeModalOpen = false;
	mergeTitle = '';
	isMerging = false;
	bridgeOrigin;
	bridgeReady;
	pendingMerge;

	connectedCallback() {
		this.showSpinner();
		getDocs({recordId: this.resolvedRecordId})
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

	get folderOptions() {
		return this.defaultFolders;
	}

	// Add documents: files upload (and attach to the record) the moment they are dropped, then sit
	// in stagedFiles until "File" stamps each one's folder and name. Closing with files still staged
	// files them anyway, so nothing is ever left unfiled; the row's X is the only way to discard one.
	get defaultUploadFolder() {
		const hasDefault = this.defaultFolders.some((folder) => folder.value === this.DEFAULT_UPLOAD_FOLDER);
		return hasDefault ? this.DEFAULT_UPLOAD_FOLDER : this.defaultFolders[0]?.value;
	}

	get hasStagedFiles() {
		return this.stagedFiles.length > 0;
	}

	get stagedRows() {
		return this.stagedFiles.map((file) => ({
			...file,
			icon: fileIcon(file.ext),
			selectLabel: `Select ${file.title}`,
			cssClass: file.selected ? 'add-doc__row add-doc__row--selected' : 'add-doc__row'
		}));
	}

	get selectedStagedCount() {
		return this.stagedFiles.filter((file) => file.selected).length;
	}

	get allStagedSelected() {
		return this.hasStagedFiles && this.selectedStagedCount === this.stagedFiles.length;
	}

	get stagedSummary() {
		const selected = this.selectedStagedCount;
		const total = this.stagedFiles.length;
		return selected ? `${selected} of ${total} selected` : `${total} file${total === 1 ? '' : 's'} ready`;
	}

	get bulkFolderLabel() {
		return this.selectedStagedCount ? 'Move selected to…' : 'Move all to…';
	}

	get fileButtonLabel() {
		const total = this.stagedFiles.length;
		return `File ${total} document${total === 1 ? '' : 's'}`;
	}

	get dropZoneClass() {
		return this.hasStagedFiles ? 'add-doc__drop add-doc__drop--compact' : 'add-doc__drop';
	}

	get addDocBodyClass() {
		return this.addDocDragging ? 'slds-modal__content add-doc add-doc--dragging' : 'slds-modal__content add-doc';
	}

	// lightning-file-upload has no size cap but only catches drops on its own small box, and its
	// insides can't be styled. So while files are dragged over the modal, the real uploader is
	// stretched (invisibly) across the whole modal body: a drop anywhere lands in it.
	handleAddDocDragEnter(event) {
		if (this.addDocDragging || !event.dataTransfer?.types?.includes('Files')) {
			return;
		}
		const uploader = this.template.querySelector('.add-doc__uploader');
		if (!uploader) {
			return;
		}
		const body = event.currentTarget.getBoundingClientRect();
		const box = uploader.getBoundingClientRect();
		// Overshoot every edge (clipped by the body) so the box's stretched rounded corners still land inside.
		const pad = 16;
		uploader.style.transform =
			`translate(${body.left - pad - box.left}px, ${body.top - pad - box.top}px) ` +
			`scale(${(body.width + 2 * pad) / box.width}, ${(body.height + 2 * pad) / box.height})`;
		this.addDocDragging = true;
	}

	handleAddDocDragOver(event) {
		// Without this, a drop that misses the uploader makes the browser open the file itself.
		if (this.addDocDragging) {
			event.preventDefault();
		}
	}

	handleAddDocDragLeave(event) {
		const body = event.currentTarget.getBoundingClientRect();
		const { clientX: x, clientY: y } = event;
		if (x <= body.left || x >= body.right || y <= body.top || y >= body.bottom) {
			this.endAddDocDrag(event);
		}
	}

	// Also wired to mousemove: no mouse events fire mid-drag, so one arriving means the drag is over
	// and the stretched uploader must stop covering the list below.
	endAddDocDrag(event) {
		if (!this.addDocDragging) {
			return;
		}
		if (event.type === 'drop') {
			// Stops the browser opening a file that somehow missed the uploader. Not a reliable
			// "missed" signal: the uploader doesn't always mark drops it took as handled.
			event.preventDefault();
		}
		const uploader = this.template.querySelector('.add-doc__uploader');
		if (uploader) {
			uploader.style.transform = '';
		}
		this.addDocDragging = false;
	}

	openAddDocumentModal() {
		this.stagedFiles = [];
		this.addDocumentModalOpen = true;
	}

	closeAddDocumentModal() {
		this.addDocumentModalOpen = false;
		this.stagedFiles = [];
	}

	handleAddDocumentClose() {
		if (this.hasStagedFiles) {
			this.fileStagedDocuments();
		} else {
			this.closeAddDocumentModal();
		}
	}

	handleUploadFinished(event) {
		const uploaded = (event.detail && event.detail.files) || [];
		const folder = this.defaultUploadFolder;
		const added = uploaded
			.filter((file) => file.contentVersionId)
			.map((file) => {
				const dot = file.name.lastIndexOf('.');
				const title = dot > 0 ? file.name.substring(0, dot) : file.name;
				return {
					documentId: file.documentId,
					contentVersionId: file.contentVersionId,
					originalTitle: title,
					title,
					ext: dot > 0 ? file.name.substring(dot + 1).toLowerCase() : '',
					folder,
					selected: false
				};
			});
		if (added.length < uploaded.length) {
			// Already attached to the record; only the filing can't be done from here.
			this.showToast('Some files were added but cannot be filed here. Use Change Folder on the row.', this.ERROR_TOAST_VARIANT);
		}
		this.stagedFiles = [...this.stagedFiles, ...added];
	}

	updateStaged(documentId, changes) {
		this.stagedFiles = this.stagedFiles.map((file) => (file.documentId === documentId ? { ...file, ...changes } : file));
	}

	handleStagedSelect(event) {
		this.updateStaged(event.target.dataset.id, { selected: event.target.checked });
	}

	handleStagedSelectAll(event) {
		const selected = event.target.checked;
		this.stagedFiles = this.stagedFiles.map((file) => ({ ...file, selected }));
	}

	handleStagedName(event) {
		this.updateStaged(event.target.dataset.id, { title: event.detail.value });
	}

	handleStagedFolder(event) {
		this.updateStaged(event.target.dataset.id, { folder: event.detail.value });
	}

	handleBulkFolder(event) {
		const folder = event.detail.value;
		const onlySelected = this.selectedStagedCount > 0;
		this.stagedFiles = this.stagedFiles.map((file) =>
			!onlySelected || file.selected ? { ...file, folder, selected: false } : file
		);
		// The combobox is a one-shot action, not a setting: clear it for the next pick.
		event.target.value = null;
	}

	handleStagedRemove(event) {
		const documentId = event.currentTarget.dataset.id;
		this.stagedFiles = this.stagedFiles.filter((file) => file.documentId !== documentId);
		deleteFile({ fileId: documentId }).catch((error) => {
			this.showToast(this.apexErrorMessage(error, 'That file could not be removed. Delete it from the list.'), this.ERROR_TOAST_VARIANT);
			this.connectedCallback();
		});
	}

	fileStagedDocuments() {
		const files = this.stagedFiles;
		this.closeAddDocumentModal();
		this.showSpinner();
		// One call per file: each has its own folder and name, and Apex renames only a single version.
		Promise.allSettled(
			files.map((file) =>
				applyUploadDetails({
					contentVersionIds: [file.contentVersionId],
					folderName: file.folder,
					documentLabel: file.title.trim() !== file.originalTitle ? file.title : ''
				})
			)
		).then((results) => {
			const failed = results.filter((result) => result.status === 'rejected').length;
			if (failed) {
				// The uploads themselves succeeded, so say so rather than implying nothing happened.
				this.showToast(`${failed} document${failed === 1 ? ' was' : 's were'} added but could not be filed. Use Change Folder on the row.`, this.ERROR_TOAST_VARIANT);
			} else {
				this.showToast(`${files.length} document${files.length === 1 ? '' : 's'} filed.`, this.SUCCESS_TOAST_VARIANT);
			}
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
		// Forget ticks on documents that are gone after a reload (deleted, or unlinked elsewhere).
		const present = new Set(this.docs.map((doc) => doc.id));
		this.selectedIds = new Set([...this.selectedIds].filter((id) => present.has(id)));
		const stillThere = this.allFolders.some((folder) => folder.name === this.selectedFolderName);
		if (!stillThere) {
			const firstWithFiles = this.allFolders.find((folder) => folder.data.length > 0);
			this.selectedFolderName = (firstWithFiles || this.allFolders[0] || {}).name;
		}
		getLoanConditions({recordId: this.resolvedRecordId})
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
			recordId : this.resolvedRecordId,
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
			recordId: this.resolvedRecordId,
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
		const order = [...this.selectedIds];
		return folder.data
			.filter((file) => this.matchesFilter(file))
			.map((file) => {
				const isSelected = this.selectedIds.has(file.id);
				let cssClass = 'dv-card';
				if (isSelected) cssClass += ' is-selected';
				if (this.hasSelection) cssClass += ' is-selecting';
				if (file.id === this.dragFileId) cssClass += ' is-dragging';
				if (file.id === this.dropTargetId) cssClass += this.dropBefore ? ' drop-before' : ' drop-after';
				const mergePosition = this.selectedIds.size > 1 && isSelected ? order.indexOf(file.id) + 1 : null;
				return { ...file, cssClass, isSelected, mergePosition, selectLabel: `Select ${file.fileNameWithType}` };
			});
	}

	// ---------- Merge into one PDF ----------

	get selectedInClickOrder() {
		const byId = new Map(this.docs.map((doc) => [doc.id, doc]));
		return [...this.selectedIds].map((id) => byId.get(id)).filter(Boolean);
	}

	// The bridge page runs on the org's Visualforce domain, which the Partner Workspace portal
	// cannot reach, so merging is offered on internal record pages only.
	get canOfferMerge() {
		return this.selectedIds.size > 1 && !this.contextRecordKey;
	}

	get mergeBlockedReason() {
		const other = this.selectedInClickOrder.find(
			(doc) => !MERGEABLE_TYPES.has(String(doc.fileType || '').toLowerCase())
		);
		return other ? `${other.fileNameWithType} is not a PDF or image, so it cannot be merged.` : '';
	}

	get mergeDisabled() {
		return Boolean(this.mergeBlockedReason);
	}

	get mergeButtonTitle() {
		return this.mergeBlockedReason || 'Merge the selected files into one PDF, in the order you ticked them';
	}

	get mergeList() {
		return this.selectedInClickOrder.map((doc, index) => ({
			id: doc.id,
			position: index + 1,
			name: doc.fileNameWithType,
			isPart: SPLIT_PART_TITLE.test(doc.fileName)
		}));
	}

	get mergePartCount() {
		return this.mergeList.filter((item) => item.isPart).length;
	}

	get mergePartNote() {
		const count = this.mergePartCount;
		if (!count) {
			return '';
		}
		return count === 1
			? 'The portal part marked below will be deleted once the merged file is saved.'
			: `The ${count} portal parts marked below will be deleted once the merged file is saved.`;
	}

	get mergeConfirmDisabled() {
		return this.isMerging || !this.mergeTitle.trim();
	}

	openMergeModal() {
		const first = this.selectedInClickOrder[0];
		const base = first.fileName.replace(SPLIT_PART_TITLE, '').trim();
		this.mergeTitle = SPLIT_PART_TITLE.test(first.fileName) ? base : `${base} (merged)`;
		this.bridgeOrigin = null;
		// Created before the iframe exists, so a ready message that arrives quickly is not missed.
		this.bridgeReady = new Promise((resolve) => {
			this.resolveBridgeReady = resolve;
		});
		this.messageHandler = this.handleBridgeMessage.bind(this);
		window.addEventListener('message', this.messageHandler);
		this.mergeModalOpen = true;
	}

	closeMergeModal() {
		if (this.isMerging) {
			return;
		}
		window.removeEventListener('message', this.messageHandler);
		this.mergeModalOpen = false;
	}

	disconnectedCallback() {
		window.removeEventListener('message', this.messageHandler);
	}

	handleMergeTitleChange(event) {
		this.mergeTitle = event.detail.value || '';
	}

	// Trusts only this org's Visualforce domain, derived from the Lightning one it is served beside.
	isBridgeOrigin(origin) {
		const myDomain = window.location.hostname.split('.')[0];
		return origin === `https://${myDomain}--c.vf.force.com`
			|| origin === `https://${myDomain}--c.sandbox.vf.force.com`;
	}

	handleBridgeMessage(event) {
		if (!this.isBridgeOrigin(event.origin) || !event.data) {
			return;
		}
		if (event.data.type === 'mergeBridgeReady') {
			this.bridgeOrigin = event.origin;
			this.resolveBridgeReady();
		} else if (event.data.type === 'mergeResult' && this.pendingMerge?.requestId === event.data.requestId) {
			const { resolve, reject } = this.pendingMerge;
			this.pendingMerge = null;
			if (event.data.ok) {
				resolve(event.data.contentVersionId);
			} else {
				reject(new Error(event.data.message || 'The merge failed.'));
			}
		}
	}

	waitForBridge() {
		let timer;
		const timeout = new Promise((resolve, reject) => {
			// eslint-disable-next-line @lwc/lwc/no-async-operation
			timer = setTimeout(
				() => reject(new Error(
					'The merge helper did not load. Ask an admin to check you have access to the Document Merge Bridge page.'
				)),
				BRIDGE_READY_TIMEOUT_MS
			);
		});
		return Promise.race([this.bridgeReady, timeout]).finally(() => clearTimeout(timer));
	}

	async handleMerge() {
		const sources = this.selectedInClickOrder;
		const title = this.mergeTitle.trim();
		const partCount = this.mergePartCount;
		this.isMerging = true;
		try {
			await this.waitForBridge();
			const requestId = `${Date.now()}-${Math.random()}`;
			// No timeout here: a long statement over a slow connection legitimately takes a while,
			// and the dialog shows it is still working.
			const mergedVersionId = await new Promise((resolve, reject) => {
				this.pendingMerge = { requestId, resolve, reject };
				this.template.querySelector('iframe.dv-merge-bridge').contentWindow.postMessage({
					type: 'merge',
					requestId,
					recordId: this.resolvedRecordId,
					title,
					sources: sources.map((doc) => ({
						versionId: doc.versionId,
						extension: String(doc.fileType).toLowerCase(),
						name: doc.fileNameWithType
					}))
				}, this.bridgeOrigin);
			});

			let deleted = 0;
			try {
				deleted = await finishMerge({
					recordId: this.resolvedRecordId,
					mergedVersionId,
					sourceDocumentIds: sources.map((doc) => doc.id)
				});
			} catch (filingError) {
				// The merged PDF is saved and on the record; only the filing and clean-up are missing.
				this.showToast(
					`${title}.pdf was saved, but it could not be filed: ${this.apexErrorMessage(filingError, 'unknown error')}. Nothing was deleted.`,
					this.ERROR_TOAST_VARIANT
				);
				this.finishMergeUi();
				return;
			}
			const leftOver = partCount - deleted;
			this.showToast(
				leftOver > 0
					? `Merged into ${title}.pdf. ${leftOver} part file(s) could not be deleted; delete them by hand.`
					: `Merged ${sources.length} files into ${title}.pdf.`,
				leftOver > 0 ? this.ERROR_TOAST_VARIANT : this.SUCCESS_TOAST_VARIANT
			);
			this.selectedIds = new Set();
			this.finishMergeUi();
		} catch (error) {
			this.isMerging = false;
			this.showToast(this.apexErrorMessage(error, 'The merge failed.'), this.ERROR_TOAST_VARIANT);
		}
	}

	finishMergeUi() {
		this.isMerging = false;
		this.closeMergeModal();
		this.connectedCallback();
	}

	get hasSelection() {
		return this.selectedIds.size > 0;
	}

	get selectionLabel() {
		const count = this.selectedIds.size;
		const inThisFolder = (this.selectedFolder?.data || []).filter((file) => this.selectedIds.has(file.id)).length;
		const elsewhere = count - inThisFolder;
		const base = `${count} selected`;
		return elsewhere ? `${base} (${elsewhere} in other folders)` : base;
	}

	get allVisibleSelected() {
		const files = this.visibleFiles;
		return files.length > 0 && files.every((file) => this.selectedIds.has(file.id));
	}

	handleToggleSelect(event) {
		const id = event.target.dataset.id;
		const next = new Set(this.selectedIds);
		if (event.target.checked) {
			next.add(id);
		} else {
			next.delete(id);
		}
		this.selectedIds = next;
	}

	// Acts on what is on screen, so with a search typed it ticks only the matches.
	handleSelectAllVisible(event) {
		const next = new Set(this.selectedIds);
		for (const file of this.visibleFiles) {
			if (event.target.checked) {
				next.add(file.id);
			} else {
				next.delete(file.id);
			}
		}
		this.selectedIds = next;
	}

	handleClearSelection() {
		this.selectedIds = new Set();
	}

	downloadSelected() {
		const files = this.docs.filter((doc) => this.selectedIds.has(doc.id));
		if (!files.length) {
			return;
		}
		this[NavigationMixin.Navigate]({
			type: 'standard__webPage',
			attributes: { url: this.getDownloadUrl(files) }
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

		moveFiles({ recordId: this.resolvedRecordId, folderName, orderedFileIds: orderedIds })
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