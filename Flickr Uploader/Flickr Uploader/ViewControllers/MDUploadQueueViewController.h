//
//  MDUploadQueueViewController.h
//  Flickr Uploader
//
//  Created by Jānis Kiršteins on 27.06.13.
//  Copyright (c) 2013. g. SIA MONTA DIGITAL. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "LXReorderableCollectionViewFlowLayout.h"

@interface MDUploadQueueViewController : UICollectionViewController<LXReorderableCollectionViewDataSource, LXReorderableCollectionViewDelegateFlowLayout>

@property (strong, nonatomic) IBOutlet UICollectionView *collectionView;

@end
